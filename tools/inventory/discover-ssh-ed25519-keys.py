#!/usr/bin/env python3
"""Discover host SSH ed25519 public keys and write them to hosts/**/meta.nix."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
from typing import Any


def run(cmd: list[str], **kwargs: Any) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, text=True, **kwargs)


def git_root() -> pathlib.Path:
    env_root = os.environ.get("GIT_ROOT")
    if env_root:
        return pathlib.Path(env_root).resolve()

    proc = run(["git", "rev-parse", "--show-toplevel"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        print("Error: not in a git repository and GIT_ROOT is not set", file=sys.stderr)
        sys.exit(1)
    return pathlib.Path(proc.stdout.strip()).resolve()


def load_hosts(root: pathlib.Path) -> list[dict[str, Any]]:
    expr = f"import {root}/tools/inventory/collect-meta.nix {{ root = {root}/hosts; }}"
    proc = run(
        ["nix", "eval", "--impure", "--json", "--expr", expr],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0:
        print(proc.stderr, file=sys.stderr, end="")
        sys.exit(proc.returncode)
    return json.loads(proc.stdout)


def selected(host: dict[str, Any], selectors: list[str]) -> bool:
    if not selectors:
        return True

    name = host["name"]
    rel_path = host["rel_path"]
    for selector in selectors:
        s = selector.rstrip("/")
        if s == name or name.startswith(s + "."):
            return True
        if s == rel_path or rel_path.startswith(s + "/"):
            return True
        if s.startswith("hosts/") and (s == rel_path or rel_path.startswith(s + "/")):
            return True
    return False


def scan_key(target: str, port: int, timeout: int) -> str:
    proc = run(
        ["ssh-keyscan", "-T", str(timeout), "-t", "ed25519", "-p", str(port), target],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0 and not proc.stdout.strip():
        raise RuntimeError(proc.stderr.strip() or f"ssh-keyscan failed with exit code {proc.returncode}")

    keys: list[str] = []
    for line in proc.stdout.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 3 and parts[1] == "ssh-ed25519":
            key = f"{parts[1]} {parts[2]}"
            if key not in keys:
                keys.append(key)

    if not keys:
        raise RuntimeError("ssh-keyscan returned no ssh-ed25519 host key")
    if len(keys) > 1:
        raise RuntimeError("ssh-keyscan returned multiple different ssh-ed25519 host keys")
    return keys[0]


def key_assignment(key: str) -> str:
    return f'  sshPublicKey = "{key}";\n'


def update_meta(meta_path: pathlib.Path, key: str) -> bool:
    text = meta_path.read_text()
    assignment = key_assignment(key)

    # Replace an existing singular assignment.
    new, count = re.subn(
        r'\n\s*sshPublicKey\s*=\s*"[^"]*";\n',
        "\n" + assignment,
        text,
        count=1,
    )
    if count:
        if new != text:
            meta_path.write_text(new)
            return True
        return False

    # Replace an existing plural assignment block with the discovered singular key.
    new, count = re.subn(
        r'\n\s*sshPublicKeys\s*=\s*\[.*?\];\n',
        "\n" + assignment,
        text,
        count=1,
        flags=re.S,
    )
    if count:
        if new != text:
            meta_path.write_text(new)
            return True
        return False

    # Insert after targetHost if possible.
    new, count = re.subn(
        r'(\n\s*targetHost\s*=\s*"[^"]+";\n)',
        r"\1" + assignment,
        text,
        count=1,
    )
    if count:
        meta_path.write_text(new)
        return True

    # Fallback: insert after lib.mk* opening brace.
    new, count = re.subn(
        r'(lib\.mk(?:Server|Router|Desktop|Host)\s*\{\n)',
        r"\1" + assignment,
        text,
        count=1,
    )
    if count:
        meta_path.write_text(new)
        return True

    raise RuntimeError("could not find insertion point in meta.nix")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Discover SSH ed25519 host public keys with ssh-keyscan and add/update hosts/**/meta.nix.",
    )
    parser.add_argument(
        "selectors",
        nargs="*",
        help="Optional host names or hosts/ paths. Defaults to every host.",
    )
    parser.add_argument("-n", "--dry-run", action="store_true", help="Print intended changes without editing files")
    parser.add_argument("-f", "--force", action="store_true", help="Update hosts that already have sshPublicKey(s)")
    parser.add_argument("-c", "--continue", dest="keep_going", action="store_true", help="Continue after failures")
    parser.add_argument("-T", "--timeout", type=int, default=5, help="ssh-keyscan timeout in seconds (default: 5)")
    parser.add_argument("-v", "--verbose", action="store_true", help="Print ssh-keyscan targets")
    args = parser.parse_args()

    root = git_root()
    os.environ["GIT_ROOT"] = str(root)
    hosts = [h for h in load_hosts(root) if selected(h, args.selectors)]

    if not hosts:
        print("No matching hosts found.", file=sys.stderr)
        return 1

    failures: list[str] = []
    changed = 0
    skipped = 0

    for host in hosts:
        name = host["name"]
        rel_path = host["rel_path"]
        deployment = host["meta"]["deployment"]
        target = deployment.get("targetHost")
        port = int(deployment.get("sshPort") or 22)
        existing = host["meta"].get("sshPublicKeys") or []
        meta_path = root / rel_path / "meta.nix"

        if not target:
            print(f"skip {name}: no targetHost")
            skipped += 1
            continue

        if existing and not args.force:
            print(f"skip {name}: sshPublicKey already set")
            skipped += 1
            continue

        try:
            if args.verbose:
                print(f"scan {name}: {target}:{port}")
            key = scan_key(target, port, args.timeout)
            old = existing[0] if existing else None

            if args.dry_run:
                if old == key:
                    print(f"unchanged {name}: {key}")
                elif old:
                    print(f"would update {name}: {old} -> {key}")
                    changed += 1
                else:
                    print(f"would add {name}: {key}")
                    changed += 1
                continue

            if update_meta(meta_path, key):
                action = "updated" if old else "added"
                print(f"{action} {name}: {key}")
                changed += 1
            else:
                print(f"unchanged {name}: {key}")
        except Exception as exc:  # noqa: BLE001 - report per-host and optionally continue
            msg = f"{name}: {exc}"
            failures.append(msg)
            print(f"error {msg}", file=sys.stderr)
            if not args.keep_going:
                return 1

    print(f"Done. changed={changed} skipped={skipped} failed={len(failures)}")
    if failures:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
