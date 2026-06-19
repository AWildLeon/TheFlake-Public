#!/usr/bin/env python3
"""Visualize deployment dependencies from hosts/**/meta.nix.

The inventory collector expands `#group` references already, so this tool uses the
same graph that mass-deployment tooling should consume.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[2]


def q(s: str) -> str:
    return json.dumps(s)


def node_id(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_]", "_", name)


def load_hosts(root: pathlib.Path) -> list[dict[str, Any]]:
    expr = f"import {root}/tools/inventory/collect-meta.nix {{ root = {root}/hosts; }}"
    out = subprocess.check_output(
        ["nix", "eval", "--impure", "--json", "--expr", expr],
        text=True,
    )
    return json.loads(out)


def build_graph(hosts: list[dict[str, Any]]) -> tuple[dict[str, Any], list[str]]:
    names = {h["name"] for h in hosts}
    tags: dict[str, set[str]] = defaultdict(set)
    for h in hosts:
        for tag in h["meta"]["deployment"].get("tags", []):
            tags[tag].add(h["name"])

    errors: list[str] = []
    graph: dict[str, Any] = {}
    for h in hosts:
        name = h["name"]
        meta = h["meta"]
        strict: list[str] = []
        for dep in meta.get("dependencies", []):
            if dep in names:
                strict.append(dep)
            elif dep in tags:
                strict.extend(sorted(tags[dep]))
            else:
                errors.append(f"{name}: unknown dependency {dep!r}")

        groups: list[dict[str, Any]] = []
        for group in meta.get("dependencyGroups", []):
            mode = group.get("mode")
            members = list(group.get("members", []))
            if mode not in {"at_least_one", "all_needed"}:
                errors.append(f"{name}: invalid dependency group mode {mode!r}")
            if not members:
                errors.append(f"{name}: empty dependency group {group.get('name', '<unnamed>')!r}")
            for member in members:
                if member not in names and member not in tags:
                    errors.append(f"{name}: unknown dependency group member {member!r}")
            groups.append(
                {
                    "name": group.get("name"),
                    "mode": mode,
                    "members": members,
                }
            )

        graph[name] = {
            "strict": list(dict.fromkeys(strict)),
            "groups": groups,
            "memberships": meta.get("dependencyGroupMemberships", []),
            "tags": meta["deployment"].get("tags", []),
        }

    # Cycle check only for strict dependencies and all_needed groups.
    strict_graph: dict[str, set[str]] = {}
    for host, data in graph.items():
        deps = set(data["strict"])
        for group in data["groups"]:
            if group["mode"] == "all_needed":
                deps.update(group["members"])
        strict_graph[host] = deps - {host}

    state: dict[str, int] = {}
    stack: list[str] = []

    def dfs(n: str) -> None:
        state[n] = 1
        stack.append(n)
        for m in strict_graph[n]:
            if m not in strict_graph:
                continue
            if state.get(m) == 1:
                errors.append("strict dependency cycle: " + " -> ".join(stack[stack.index(m) :] + [m]))
            elif state.get(m, 0) == 0:
                dfs(m)
        stack.pop()
        state[n] = 2

    for n in strict_graph:
        if state.get(n, 0) == 0:
            dfs(n)

    return graph, errors


def filter_graph(graph: dict[str, Any], roots: list[str], reverse: bool) -> dict[str, Any]:
    if not roots:
        return graph

    edges: dict[str, set[str]] = defaultdict(set)
    for host, data in graph.items():
        for dep in data["strict"]:
            edges[host].add(dep)
        for group in data["groups"]:
            for dep in group["members"]:
                edges[host].add(dep)

    if reverse:
        rev: dict[str, set[str]] = defaultdict(set)
        for host, deps in edges.items():
            for dep in deps:
                rev[dep].add(host)
        edges = rev

    seen: set[str] = set()

    def walk(n: str) -> None:
        if n in seen:
            return
        seen.add(n)
        for m in edges.get(n, set()):
            walk(m)

    for root in roots:
        walk(root)
    return {k: v for k, v in graph.items() if k in seen}


def render_text(graph: dict[str, Any]) -> str:
    lines: list[str] = []
    for host in sorted(graph):
        data = graph[host]
        lines.append(host)
        if data["strict"]:
            lines.append("  all_needed: " + ", ".join(data["strict"]))
        for group in data["groups"]:
            label = group["mode"]
            if group.get("name"):
                label += f" #{group['name']}"
            lines.append(f"  {label}: " + ", ".join(group["members"]))
        if data["memberships"]:
            lines.append("  member_of: " + ", ".join(f"#{g}" for g in data["memberships"]))
    return "\n".join(lines) + "\n"


def render_mermaid(graph: dict[str, Any]) -> str:
    lines = ["flowchart LR"]
    for host in sorted(graph):
        lines.append(f"  {node_id(host)}[{q(host)}]")
    for host, data in sorted(graph.items()):
        h = node_id(host)
        for dep in data["strict"]:
            if dep in graph:
                lines.append(f"  {node_id(dep)} --> {h}")
        for idx, group in enumerate(data["groups"]):
            gname = group.get("name") or f"{host}_group_{idx}"
            gid = node_id(f"group_{host}_{gname}_{idx}")
            label = f"{group['mode']}"
            if group.get("name"):
                label += f" #{group['name']}"
            lines.append(f"  {gid}{{{q(label)}}}")
            lines.append(f"  {gid} -.-> {h}")
            for member in group["members"]:
                if member in graph:
                    lines.append(f"  {node_id(member)} -.-> {gid}")
    return "\n".join(lines) + "\n"


def render_svg(graph: dict[str, Any]) -> str:
    mmdc = shutil.which("mmdc")
    if not mmdc:
        raise RuntimeError("Mermaid CLI not found: install/run with `mermaid-cli` so `mmdc` is on PATH")

    with tempfile.TemporaryDirectory(prefix="dependency-graph-") as tmp:
        tmpdir = pathlib.Path(tmp)
        input_path = tmpdir / "graph.mmd"
        output_path = tmpdir / "graph.svg"
        input_path.write_text(render_mermaid(graph))
        subprocess.run(
            [mmdc, "-i", str(input_path), "-o", str(output_path), "-b", "transparent"],
            check=True,
            capture_output=True,
            text=True,
        )
        return output_path.read_text()


def render_dot(graph: dict[str, Any]) -> str:
    lines = ["digraph dependencies {", "  rankdir=LR;", "  node [shape=box];"]
    for host in sorted(graph):
        lines.append(f"  {q(host)};")
    for host, data in sorted(graph.items()):
        for dep in data["strict"]:
            if dep in graph:
                lines.append(f"  {q(dep)} -> {q(host)};")
        for idx, group in enumerate(data["groups"]):
            gname = group.get("name") or f"{host}_group_{idx}"
            gid = f"group:{host}:{gname}:{idx}"
            label = group["mode"] + (f" #{group['name']}" if group.get("name") else "")
            lines.append(f"  {q(gid)} [label={q(label)}, shape=diamond, style=dashed];")
            lines.append(f"  {q(gid)} -> {q(host)} [style=dashed];")
            for member in group["members"]:
                if member in graph:
                    lines.append(f"  {q(member)} -> {q(gid)} [style=dashed];")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flake-root", type=pathlib.Path, default=ROOT)
    parser.add_argument("--format", choices=["text", "mermaid", "svg", "dot", "json"], default="mermaid")
    parser.add_argument("--output", "-o", type=pathlib.Path, help="Write output to this file instead of stdout")
    parser.add_argument("--host", action="append", default=[], help="Limit to this host and its dependencies")
    parser.add_argument("--reverse", action="store_true", help="With --host, show dependents instead of dependencies")
    parser.add_argument("--no-validate", action="store_true", help="Do not fail on missing refs/cycles")
    args = parser.parse_args()

    hosts = load_hosts(args.flake_root)
    graph, errors = build_graph(hosts)
    if errors and not args.no_validate:
        print("Dependency graph validation failed:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    graph = filter_graph(graph, args.host, args.reverse)
    if args.format == "text":
        rendered = render_text(graph)
    elif args.format == "mermaid":
        rendered = render_mermaid(graph)
    elif args.format == "svg":
        try:
            rendered = render_svg(graph)
        except subprocess.CalledProcessError as e:
            print(f"failed to render SVG with Mermaid CLI: {e}", file=sys.stderr)
            if e.stderr:
                print(e.stderr, file=sys.stderr, end="")
            return 1
        except (OSError, RuntimeError) as e:
            print(f"failed to render SVG with Mermaid CLI: {e}", file=sys.stderr)
            return 1
    elif args.format == "dot":
        rendered = render_dot(graph)
    else:
        rendered = json.dumps(graph, indent=2, sort_keys=True) + "\n"

    if args.output:
        args.output.write_text(rendered)
    else:
        print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
