#!/usr/bin/env python3
"""Sync Proxmox VMs to the desired state declared in proxmox.nix files."""

import argparse
import base64
import binascii
import concurrent.futures
import fnmatch
import json
import os
import pathlib
import re
import socket
import subprocess
import sys
import tempfile
import time
import urllib.parse
from typing import Any, Dict, List, NoReturn, Optional, Tuple

try:
    from proxmoxer import ProxmoxAPI
except ImportError:
    print("Error: proxmoxer not installed. Run inside the nix dev shell.", file=sys.stderr)
    sys.exit(1)


# Keys consumed by this tool; never forwarded to the PVE API.
TOOL_FIELDS = {"vmid", "node", "template"}

# Tag stamped on every VM the tool owns. Only VMs carrying this tag are
# eligible for --prune deletion, so unrelated VMs are never touched.
DEFAULT_MANAGED_TAG = "proxmox-sync"

# Minimum PVE privileges required by this tool.
SYNC_PRIVS = [
    "Datastore.AllocateSpace",  # write disk image when cloning
    "Datastore.Audit",          # read storage info
    "SDN.Use",                  # attach a NIC to an SDN VNet/zone bridge
    "Sys.Audit",                # cluster status, node list, nextid, task status
    "VM.Allocate",              # create / delete VMs
    "VM.Audit",                 # read VM config and status
    "VM.Clone",                 # clone templates
    "VM.Config.CDROM",          # cloud-init ISO drive
    "VM.Config.CPU",
    "VM.Config.Disk",
    "VM.Config.HWType",         # machine type, BIOS
    "VM.Config.Memory",
    "VM.Config.Network",
    "VM.Config.Options",        # boot order, agent, tags, description, …
    "VM.PowerMgmt",             # start / stop
]


def fail(msg: str) -> NoReturn:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def _confirm(prompt: str) -> bool:
    """Ask an interactive yes/no question; default is no. Returns True only for y/yes.

    EOF (e.g. non-interactive stdin) is treated as 'no'. Ctrl-C is NOT caught
    here: it propagates to the top-level handler so pressing it at any prompt —
    including the reboot prompt — exits the whole program cleanly.
    """
    try:
        return input(f"{prompt} [y/N] ").strip().lower() in ("y", "yes")
    except EOFError:
        print()
        return False


# ── Ignore rules (.proxmoxignore) ──────────────────────────────────────────────

def _parse_rule(line: str) -> Optional[Tuple[bool, str]]:
    s = line.strip()
    if not s or s.startswith("#"):
        return None
    if s.startswith(r"\#") or s.startswith(r"\!"):
        s = s[1:]
    negated = s.startswith("!")
    if negated:
        s = s[1:].strip()
    return (negated, s) if s else None


def load_ignore_rules(
    inline: List[str], files: List[pathlib.Path]
) -> List[Tuple[bool, str]]:
    rules: List[Tuple[bool, str]] = []
    for raw in inline:
        p = _parse_rule(raw)
        if p:
            rules.append(p)
    for f in files:
        if not f.exists():
            continue
        for line in f.read_text(encoding="utf-8-sig").splitlines():
            p = _parse_rule(line)
            if p:
                rules.append(p)
    return rules


def is_ignored(vm_name: str, field: str, rules: List[Tuple[bool, str]]) -> bool:
    """Match key 'vm_name|field' against rules; last match wins."""
    key = f"{vm_name}|{field}"
    result = False
    for negated, pattern in rules:
        if fnmatch.fnmatch(key, pattern):
            result = not negated
    return result


# ── Credential env file ────────────────────────────────────────────────────────

def load_env_file(path: str) -> Dict[str, str]:
    result: Dict[str, str] = {}
    expanded = os.path.expanduser(path)
    try:
        with open(expanded) as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" not in line:
                    continue
                k, _, v = line.partition("=")
                result[k.strip()] = v.strip()
    except FileNotFoundError:
        fail(f"env file not found: {expanded}")
    return result


# ── Proxmox connection ─────────────────────────────────────────────────────────

def connect(url: str, env: Dict[str, str], verify_ssl: bool) -> "ProxmoxAPI":
    host = re.sub(r"^https?://", "", url).rstrip("/")
    port = 8006
    if ":" in host:
        host, p = host.rsplit(":", 1)
        try:
            port = int(p)
        except ValueError:
            fail(f"Invalid port in URL {url!r}: {p!r}")

    if "PROXMOX_TOKEN_ID" in env and "PROXMOX_TOKEN_SECRET" in env:
        tid = env["PROXMOX_TOKEN_ID"]
        if "!" not in tid:
            fail(f"PROXMOX_TOKEN_ID must be user@realm!tokenname, got: {tid!r}")
        user, token_name = tid.rsplit("!", 1)
        return ProxmoxAPI(
            host,
            port=port,
            user=user,
            token_name=token_name,
            token_value=env["PROXMOX_TOKEN_SECRET"],
            verify_ssl=verify_ssl,
            timeout=30,
        )
    elif "PROXMOX_USER" in env and "PROXMOX_PASSWORD" in env:
        return ProxmoxAPI(
            host,
            port=port,
            user=env["PROXMOX_USER"],
            password=env["PROXMOX_PASSWORD"],
            verify_ssl=verify_ssl,
            timeout=30,
        )
    else:
        fail(
            "env file must contain either PROXMOX_TOKEN_ID + PROXMOX_TOKEN_SECRET "
            "or PROXMOX_USER + PROXMOX_PASSWORD"
        )


def resolve_pve_node(proxmox: "ProxmoxAPI", node_cfg: Dict[str, Any]) -> str:
    """Return the PVE cluster node name to use for API calls."""
    if "nodeName" in node_cfg:
        return node_cfg["nodeName"]
    nodes = proxmox.nodes.get()
    if len(nodes) == 1:
        return nodes[0]["node"]
    names = [n["node"] for n in nodes]
    fail(
        f"Multiple PVE nodes found {names}. "
        "Add 'nodeName' to the entry in proxmox/nodes.nix."
    )


# ── Task polling ───────────────────────────────────────────────────────────────

def wait_task(proxmox: "ProxmoxAPI", node: str, upid: str, timeout: int = 300) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        s = proxmox.nodes(node).tasks(upid).status.get()
        if s.get("status") == "stopped":
            if s.get("exitstatus") == "OK":
                return
            fail(f"Task {upid} failed: {s.get('exitstatus')}")
        time.sleep(2)
    fail(f"Task {upid} timed out after {timeout}s")


def _is_template(vm_info: Dict[str, Any]) -> bool:
    """True if a PVE qemu entry is a template (template=1 in list/config output)."""
    val = vm_info.get("template")
    return str(val) in ("1", "True", "true")


# ── Managed-tag helpers ────────────────────────────────────────────────────────

def _split_tags(tags_str: str) -> List[str]:
    return [t.strip() for t in tags_str.split(";") if t.strip()]


def _tags(vm_info: Dict[str, Any]) -> str:
    """Return the tags string from a VM info dict, never None or 'None'."""
    return str(vm_info.get("tags") or "")


def has_managed_tag(tags_str: str, tag: str) -> bool:
    return tag in _split_tags(tags_str)


def merge_managed_tag(tags_str: str, tag: str) -> str:
    """Return tags string with tag added if absent, preserving existing tags."""
    parts = _split_tags(tags_str)
    if tag not in parts:
        parts.append(tag)
    return ";".join(parts)


def _with_managed_tag(cfg: Dict[str, Any], managed_tag: str) -> Dict[str, Any]:
    """Return a copy of a desired config with the tool's managed tag folded into tags.

    The managed tag is owned by proxmox-sync and is never written in proxmox.nix.
    Folding it into the desired tags before diffing keeps its presence on the VM
    from showing as drift, while still treating its absence as a real change.
    """
    out = dict(cfg)
    out["tags"] = merge_managed_tag(str(cfg.get("tags") or ""), managed_tag)
    return out


# ── Auto vmid assignment ───────────────────────────────────────────────────────

def write_vmid(repo: pathlib.Path, vm_name: str, vmid: int) -> None:
    """Write the assigned vmid back into the host's proxmox.nix file."""
    path = repo / "hosts" / pathlib.Path(*vm_name.split(".")) / "proxmox.nix"
    if not path.exists():
        print(f"  WARN: {path} not found — cannot write back vmid", file=sys.stderr)
        return

    content = path.read_text()

    # Case 1: vmid = null; already in file → replace it
    if re.search(r"\bvmid\s*=\s*null\s*;", content):
        new_content = re.sub(r"\bvmid\s*=\s*null\s*;", f"vmid = {vmid};", content)
        path.write_text(new_content)
        print(f"  Wrote vmid = {vmid} → {path.relative_to(repo)}")
        return

    # Case 2: vmid absent — inject after `// {` (let…in base // { … }) or first `{`
    m = re.search(r"//\s*\{", content)
    if not m:
        m = re.search(r"(?<!\$)\{", content)
    if not m:
        print(f"  WARN: couldn't locate attrset in {path} to inject vmid", file=sys.stderr)
        return

    insert_at = m.end()
    new_content = content[:insert_at] + f"\n  vmid = {vmid};" + content[insert_at:]
    path.write_text(new_content)
    print(f"  Wrote vmid = {vmid} → {path.relative_to(repo)}")


# ── Post-create deployment ─────────────────────────────────────────────────────

def _extract_ip(ipconfig_str: str) -> Optional[str]:
    """Pull the bare IP from 'ip=1.2.3.4/24,gw=...' style cloud-init string."""
    m = re.search(r"ip=(\d+\.\d+\.\d+\.\d+)", ipconfig_str)
    return m.group(1) if m else None


def wait_for_ssh(host: str, port: int = 22, timeout: int = 300) -> bool:
    print(f"         Waiting for SSH on {host}:{port} (up to {timeout}s)…")
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection((host, port), timeout=5):
                print(f"         SSH is up.")
                return True
        except (socket.timeout, ConnectionRefusedError, OSError):
            time.sleep(5)
    return False


def _colmena_target_host(host_dir: pathlib.Path) -> Optional[str]:
    """Return deployment.targetHost from a host's meta.json, or None if unset.

    This is the address colmena deploys to; without it the post-create
    `colmena apply` has nowhere to connect.
    """
    try:
        data = json.loads((host_dir / "meta.json").read_text())
    except Exception:
        return None
    th = (data.get("deployment") or {}).get("targetHost")
    return str(th) if th else None


def colmena_deploy(flake_root: str, vm_name: str, fresh_host: bool = False) -> bool:
    # Use the `boot` goal (not `switch`): make the new generation the boot
    # default without live-activating it, which avoids activation failures on
    # freshly cloned VMs where the delta from the template config is too large.
    # We deliberately do NOT pass `--reboot` — that would block until the node
    # comes back up. The caller triggers a non-blocking reboot via the PVE API
    # instead, so the new generation boots without the tool waiting on it.
    print(f"         Running: colmena apply boot --on {vm_name!r}")

    env = os.environ.copy()
    tmp_ssh_cfg: Optional[str] = None
    if fresh_host:
        # A freshly created VM generates brand-new SSH host keys (and may do so
        # again if it's ever recreated), so don't verify or persist them —
        # otherwise the next deploy trips 'REMOTE HOST IDENTIFICATION HAS CHANGED'
        # or pollutes ~/.ssh/known_hosts. Hand colmena an ssh config (it honours
        # SSH_CONFIG_FILE for both the closure copy and activation) that throws
        # the host key away.
        fd, tmp_ssh_cfg = tempfile.mkstemp(prefix="proxmox-sync-ssh-", suffix=".config")
        with os.fdopen(fd, "w") as f:
            f.write(
                "Host *\n"
                "    StrictHostKeyChecking no\n"
                "    UserKnownHostsFile /dev/null\n"
                "    GlobalKnownHostsFile /dev/null\n"
                "    LogLevel ERROR\n"
            )
        env["SSH_CONFIG_FILE"] = tmp_ssh_cfg
        # Belt-and-suspenders for the `nix copy` step, which uses NIX_SSHOPTS.
        env["NIX_SSHOPTS"] = (
            env.get("NIX_SSHOPTS", "")
            + " -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
            + " -o GlobalKnownHostsFile=/dev/null"
        ).strip()
        print("         (new host: ignoring SSH host key, not recording known_hosts)")

    try:
        r = subprocess.run(
            ["colmena", "apply", "boot", "--on", vm_name],
            cwd=flake_root,
            env=env,
        )
        return r.returncode == 0
    finally:
        if tmp_ssh_cfg:
            try:
                os.unlink(tmp_ssh_cfg)
            except OSError:
                pass


# ── Disk helpers ──────────────────────────────────────────────────────────────

# efidisk0 / tpmstate0 carry a PVE-assigned volume in the same 'storage:vol,opts'
# format as ordinary disks, so a desired spec that omits the volume (e.g.
# 'fast:efitype=4m,...') must borrow the current one and compare size-aware —
# exactly like virtio/scsi/sata/ide. Without them here they fall back to a plain
# string compare and report perpetual drift on the missing volume token.
_DISK_RE   = re.compile(r'^(virtio|scsi|sata|ide|efidisk|tpmstate)\d+$')
_UNUSED_RE = re.compile(r'^unused\d+$')


def _get_unused_disks(cfg: Dict[str, Any]) -> Dict[str, str]:
    """Return all unusedN fields from a PVE VM config (detached but not deleted)."""
    return {k: str(v) for k, v in cfg.items() if _UNUSED_RE.match(k)}


def _disk_size(disk_str: str) -> Optional[str]:
    """Extract the size token from a PVE disk string (e.g. '32G')."""
    m = re.search(r'\bsize=(\d+[KMGT]?)\b', str(disk_str), re.IGNORECASE)
    return m.group(1) if m else None


_SIZE_UNITS = {"K": 1024, "M": 1024**2, "G": 1024**3, "T": 1024**4}


def _size_bytes(size_str: str) -> Optional[int]:
    """Parse a PVE size string like '32G' or '1024M' to bytes for unit-safe comparison."""
    m = re.fullmatch(r'(\d+)([KMGT]?)', size_str.strip(), re.IGNORECASE)
    if not m:
        return None
    n, unit = int(m.group(1)), m.group(2).upper()
    return n * _SIZE_UNITS.get(unit, 1)


def _disk_base(disk_str: str) -> str:
    """Strip size= from a PVE disk string for comparing non-size attributes."""
    return re.sub(r',?size=\d+[KMGT]?\b', '', str(disk_str), flags=re.IGNORECASE).strip(',')


def _split_disk(disk_str: str) -> Tuple[Optional[str], List[str]]:
    """Split a PVE disk string into (volume, options).

    The volume is the lone comma-token without '=' (e.g.
    'fast:115/vm-115-disk-0.raw', or a 'storage:SIZE' allocation request);
    everything with '=' is an option ('discard=on', 'size=80G', …).

    A volume reference never contains '='. If the first token glues a storage
    prefix straight onto an option (e.g. 'fast:discard=on' — what's left after
    removing a disk's volume name but keeping its 'fast:' storage), the
    'storage:' is a dangling hint with no volume id. Strip it so the option
    parses cleanly; the current disk's volume is borrowed instead (see
    _disk_put_value). Genuine 'storage:SIZE' allocations like 'fast:30' carry no
    '=' and are left intact, and 'storage:size=NN' allocations still survive via
    _disk_put_value's no-current-volume branch, which returns the spec verbatim.
    """
    toks = [t for t in str(disk_str).split(",") if t]
    if toks:
        m = re.match(r'^[A-Za-z0-9_-]+:(.+=.*)$', toks[0])
        if m:
            toks[0] = m.group(1)
    volume = next((t for t in toks if "=" not in t), None)
    opts = [t for t in toks if "=" in t]
    return volume, opts


def _disk_put_value(desired: str, current: str) -> str:
    """Disk string for config.put, borrowing the volume when `desired` omits it.

    A spec like 'discard=on,size=80G' carries no volume reference; sent on its
    own PVE rejects it ('virtioN.file: property is missing'). When `current`
    already has a volume (e.g. a freshly cloned disk), splice the desired
    options onto that volume so the existing disk is updated in place. size= is
    dropped here — growth is applied via the resize API, which config.put can't
    do. Fully-specified specs (own volume / storage:SIZE) pass through unchanged.
    """
    d_vol, d_opts = _split_disk(desired)
    if d_vol is not None:
        return str(desired)
    c_vol, _ = _split_disk(current)
    if c_vol is None:
        return str(desired)
    opts = [o for o in d_opts if _disk_size(o) is None]
    return ",".join([c_vol] + opts)


def _disk_changed(desired: str, current: str) -> bool:
    """True if a desired disk spec implies a real change vs the current PVE value.

    Mirrors the apply logic (see the UPDATE branch): a desired spec may omit its
    volume — in which case it borrows the current disk's volume — and any growth
    is applied through the resize API. So neither a borrowed-back volume nor a
    pure unit restatement of size (e.g. '80G' vs '81920M') counts as drift; only
    a real size change or a differing non-size attribute does.
    """
    new_sz, cur_sz = _disk_size(desired), _disk_size(current)
    if new_sz:
        nb = _size_bytes(new_sz)
        cb = _size_bytes(cur_sz) if cur_sz else None
        # A grow or shrink (in bytes) is a change; a unit-only restatement is not.
        if nb is not None and (cb is None or nb != cb):
            return True
    # Compare non-size attributes against the volume the spec would actually use.
    put_val = _disk_put_value(desired, current)
    return _disk_base(put_val) != _disk_base(current)


# ── Config diff ────────────────────────────────────────────────────────────────

_NET_RE = re.compile(r'^net\d+$')


def _net_queues(s: str) -> Optional[str]:
    """Extract the queues= value from a PVE net string, or None if absent."""
    m = re.search(r'\bqueues=(\d+)', str(s))
    return m.group(1) if m else None


def _queues_changed(desired: str, current: str) -> bool:
    """Return True if the queues= count differs between two net strings."""
    return _net_queues(desired) != _net_queues(current)


# PVE auto-assigns a MAC and returns e.g. 'virtio=BC:24:11:48:97:95,bridge=vmbr0'.
# Strip it so 'virtio,bridge=vmbr0' in desired doesn't perpetually show as drifted.
# If the user explicitly writes a MAC in desired, it gets stripped here too for the
# comparison; on write the current MAC is re-injected (see _inject_net_mac) so a netN
# update — e.g. a queues or bridge change — never makes PVE assign a fresh MAC.
# Match any PVE network driver name (word chars) followed by =MAC, covering
# virtio, e1000, e1000e, vmxnet3, rtl8139, ne2k_pci, pcnet, i82551, etc.
_NET_MAC_RE = re.compile(
    r'\b(\w+)=[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}\b'
)


def _net_mac(s: str) -> Optional[str]:
    """Extract the MAC address from a PVE net string, or None if absent."""
    m = _NET_MAC_RE.search(str(s))
    return m.group(0).split('=', 1)[1] if m else None


def _inject_net_mac(desired: str, mac: str) -> str:
    """Attach mac to the model token of a net string if it carries no MAC.

    PVE stores the MAC on the model field, e.g. 'virtio=BC:24:..,bridge=vmbr0'.
    Desired strings written by mkNet omit it ('virtio,bridge=vmbr0'), so writing
    one back would make PVE auto-assign a fresh MAC. Re-attach the current MAC to
    keep it stable. If desired already pins a MAC, leave it untouched.
    """
    if _NET_MAC_RE.search(desired):
        return desired  # desired already pins a MAC
    parts = desired.split(',')
    # mkNet emits the bare model as the first comma-separated token.
    if parts and '=' not in parts[0]:
        parts[0] = f"{parts[0]}={mac}"
        return ','.join(parts)
    return desired


def _norm(field: str, v: Any) -> str:
    """Normalise a field value for comparison.

    sshkeys: PVE stores them URL-encoded; desired config has plain text.
    netN:    PVE appends an auto-assigned MAC; strip it for comparison.
    diskN:   Normalize size units to bytes so '15G' == '15360M'.
    tags:    PVE may return tags in a different order; sort them so order
             doesn't show as drift.
    bool:    Nix true/false → Python True/False; PVE stores as 1/0.
    """
    # bool must be checked before int because bool is a subclass of int.
    if isinstance(v, bool):
        return "1" if v else "0"
    if field == "tags":
        # PVE returns tags as a ';'-separated list and may reorder them, so
        # decode each tag separately, drop duplicates, and sort for a stable
        # order-independent comparison.
        return ";".join(sorted(set(_split_tags(str(v)))))
    if field == "sshkeys":
        decoded = urllib.parse.unquote(str(v))
        return "\n".join(sorted(line.strip() for line in decoded.splitlines() if line.strip()))
    if _NET_RE.match(field):
        return _NET_MAC_RE.sub(r'\1', str(v)).strip()
    if _DISK_RE.match(field):
        s = str(v)
        m = re.search(r'\bsize=(\d+[KMGT]?)\b', s, re.IGNORECASE)
        if m:
            nb = _size_bytes(m.group(1))
            if nb is not None:
                s = re.sub(r'\bsize=\d+[KMGT]?\b', f'size={nb}', s, flags=re.IGNORECASE)
        return s.strip()
    if field == "smbios1":
        # Decode base64 fields and strip UUID for comparison. Users write human-readable
        # values in proxmox.nix; the tool encodes them before sending to PVE and decodes
        # them here for comparison. UUID is PVE-managed and preserved on write.
        return _smbios_normalize(str(v))
    return str(v).strip()


# ── SMBIOS helpers ─────────────────────────────────────────────────────────────

def _smbios_uuid(s: str) -> Optional[str]:
    """Extract the uuid value from a PVE smbios1 string."""
    m = re.search(r'\buuid=([^,]+)', str(s), re.IGNORECASE)
    return m.group(1) if m else None


def _strip_smbios_uuid(s: str) -> str:
    """Remove uuid= and base64= metadata from a smbios1 string, preserving user fields."""
    parts = [
        p for p in str(s).split(',')
        if p and not p.strip().lower().startswith(('uuid=', 'base64='))
    ]
    return ','.join(parts)


def _inject_smbios_uuid(desired: str, uuid: str) -> str:
    """Prepend uuid=<uuid> to a smbios1 string if uuid is not already present."""
    if 'uuid=' in desired.lower():
        return desired
    return f"uuid={uuid},{desired}" if desired else f"uuid={uuid}"


def _b64decode_smbios_val(val: str) -> str:
    """Try to base64-decode a SMBIOS field value; return as-is if it isn't base64."""
    try:
        padded = val + '=' * (-len(val) % 4)
        return base64.b64decode(padded, validate=True).decode('utf-8')
    except (binascii.Error, UnicodeDecodeError, ValueError):
        return val


def _b64encode_smbios_val(val: str) -> str:
    """Base64-encode a SMBIOS field value if it isn't already base64."""
    if re.fullmatch(r'[A-Za-z0-9+/]+=*', val):
        return val  # already base64
    return base64.b64encode(val.encode()).decode()


def _smbios_normalize(s: str) -> str:
    """Decode base64 SMBIOS fields and sort key=value pairs for stable comparison.

    UUID is stripped (it is PVE-managed and not part of desired config).
    """
    parts = []
    for part in _strip_smbios_uuid(str(s)).split(','):
        if not part:
            continue
        if '=' in part:
            k, _, v = part.partition('=')
            parts.append(f"{k.strip()}={_b64decode_smbios_val(v)}")
        else:
            parts.append(part)
    return ','.join(sorted(parts))


def _smbios_encode_fields(s: str) -> str:
    """Base64-encode all user fields in a smbios1 string and set base64=1 flag.

    PVE requires base64=1 to indicate that the string fields are base64-encoded.
    uuid= and base64= are literal metadata fields and are passed through unchanged.
    """
    parts = []
    has_base64_flag = False
    for part in str(s).split(','):
        if not part:
            continue
        if '=' in part:
            k, _, v = part.partition('=')
            k = k.strip()
            kl = k.lower()
            if kl == 'uuid':
                parts.append(part)
            elif kl == 'base64':
                has_base64_flag = True
                parts.append(part)
            else:
                parts.append(f"{k}={_b64encode_smbios_val(v)}")
        else:
            parts.append(part)
    if not has_base64_flag:
        parts.append('base64=1')
    return ','.join(parts)


def _preprocess_api(cfg: Dict[str, Any]) -> Dict[str, Any]:
    """Transform config values into the format PVE expects before an API call."""
    out = dict(cfg)
    if "sshkeys" in out:
        out["sshkeys"] = urllib.parse.quote(str(out["sshkeys"]), safe="")
    if "smbios1" in out:
        out["smbios1"] = _smbios_encode_fields(str(out["smbios1"]))
    return out


def diff_config(
    desired: Dict[str, Any],
    current: Dict[str, Any],
    vm_name: str,
    rules: List[Tuple[bool, str]],
) -> Dict[str, Any]:
    """Return desired fields that differ from current, excluding ignored fields.

    A desired value of None means "delete this field from the VM".
    """
    delta: Dict[str, Any] = {}
    for k, v in desired.items():
        if is_ignored(vm_name, k, rules):
            continue
        cur = current.get(k)
        if v is None:
            # Explicit null → delete only if the field currently exists on the VM.
            if cur is not None:
                delta[k] = None
        elif cur is None:
            delta[k] = v
        elif _DISK_RE.match(k):
            # Disks need volume/size-aware comparison: a spec without its own
            # volume borrows the current one and grows are done via resize, so a
            # plain _norm string compare would report spurious drift.
            if _disk_changed(str(v), str(cur)):
                delta[k] = v
        elif _norm(k, v) != _norm(k, cur):
            delta[k] = v
    return delta


# ── Pending-change / reboot helpers ───────────────────────────────────────────

# PVE cannot hot-apply these fields to a running VM; they queue as "pending"
# until the next stop+start (or reboot).
_REBOOT_REQUIRED_FIELDS = {
    "balloon", "bios", "cores", "cpu", "kvm", "machine",
    "memory", "numa", "ostype", "rng0", "scsihw",
    "serial0", "sockets", "vcpus", "vga",
}


def get_pending_changes(proxmox: "ProxmoxAPI", node: str, vmid: int) -> Dict[str, Any]:
    """Return fields that PVE has queued as pending (require stop+start to apply)."""
    try:
        rows = proxmox.nodes(node).qemu(vmid).pending.get()
        return {
            r["key"]: {"current": r.get("value"), "pending": r.get("pending")}
            for r in (rows or [])
            if "pending" in r
        }
    except Exception:
        return {}


def _poll_task_ok(proxmox: "ProxmoxAPI", node: str, upid: str, timeout: int = 120) -> bool:
    """Poll a PVE task; return True if it completed with OK, False otherwise."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            s = proxmox.nodes(node).tasks(upid).status.get()
        except Exception:
            return False
        if s.get("status") == "stopped":
            return s.get("exitstatus") == "OK"
        time.sleep(2)
    return False


def _agent_running(proxmox: "ProxmoxAPI", node: str, vmid: int) -> bool:
    """Return True if the QEMU guest agent is reachable."""
    try:
        proxmox.nodes(node).qemu(vmid).agent.ping.post()
        return True
    except Exception:
        return False


def _wait_stopped(proxmox: "ProxmoxAPI", node: str, vmid: int, timeout: int) -> bool:
    """Poll VM status until stopped or timeout. Returns True if stopped."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            st = proxmox.nodes(node).qemu(vmid).status.current.get()
            if st.get("status") == "stopped":
                return True
        except Exception:
            pass
        time.sleep(3)
    return False


def _rollback_created_vm(
    proxmox: "ProxmoxAPI",
    node: str,
    vmid: int,
    vm_name: str,
    args: argparse.Namespace,
) -> None:
    """Offer to delete a VM that was cloned but failed during post-create setup.

    Cloning succeeded but a later step (config.put / resize / start) raised, so a
    half-configured VM is left behind. Prompt to remove it unless --yes auto-approves.
    """
    if not (getattr(args, "yes", False) or _confirm(
        f"         VM {vmid} ({vm_name}) was created but setup failed — delete it?"
    )):
        print(f"         Leaving VM {vmid} in place.")
        return
    try:
        st = proxmox.nodes(node).qemu(vmid).status.current.get()
        if st.get("status") != "stopped":
            print(f"         Stopping VM {vmid}…")
            wait_task(proxmox, node, proxmox.nodes(node).qemu(vmid).status.stop.post())
        upid = proxmox.nodes(node).qemu(vmid).delete()
        if upid:
            wait_task(proxmox, node, upid)
        print(f"         Rolled back — deleted VM {vmid}.")
    except Exception as e:
        print(f"         WARN: rollback delete failed: {e}", file=sys.stderr)


_BACKUP_DIR = ".proxmox-backups"


def backup_vm_config(
    root: str,
    pve_node: str,
    vmid: int,
    vm_name: str,
    cfg: Dict[str, Any],
) -> str:
    """Dump a VM's current config to a gitignored backup file before mutating it.

    Writes <root>/.proxmox-backups/<vmid>-<vm_name>/<UTC-timestamp>.json holding the
    config as PVE returned it. This is a config snapshot only — for a destroyed VM or a
    pruned unusedN disk it records the volume *reference*, not the disk *data*, so it is
    not a restore point for deleted disk contents. Raises on write failure so the caller
    can fail closed and skip the change rather than mutate a VM with no backup.
    """
    safe_name = re.sub(r'[^A-Za-z0-9._-]', '_', str(vm_name)) or "vm"
    dest_dir = os.path.join(root, _BACKUP_DIR, f"{vmid}-{safe_name}")
    os.makedirs(dest_dir, exist_ok=True)
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    path = os.path.join(dest_dir, f"{stamp}.json")
    payload = {
        "vmid": vmid,
        "name": vm_name,
        "node": pve_node,
        "captured": stamp,
        "config": cfg,
    }
    with open(path, "w") as fh:
        json.dump(payload, fh, indent=2, sort_keys=True, default=str)
    return path


def shutdown_start_vm(proxmox: "ProxmoxAPI", node: str, vmid: int) -> None:
    """Shut down a VM gracefully then start it to apply pending config changes.

    Shutdown priority:
      1. Guest agent shutdown (most graceful — bypasses ACPI, signals the OS directly)
      2. ACPI shutdown with 5-minute PVE-side timeout
      3. Force stop (last resort, with warning)
    """
    stopped = False

    # 1 — guest agent
    if _agent_running(proxmox, node, vmid):
        try:
            proxmox.nodes(node).qemu(vmid).agent.shutdown.post()
            stopped = _wait_stopped(proxmox, node, vmid, timeout=120)
        except Exception:
            pass

    # 2 — ACPI shutdown (PVE manages its own timeout via the timeout param)
    if not stopped:
        try:
            upid = proxmox.nodes(node).qemu(vmid).status.shutdown.post(timeout=300)
            if upid:
                stopped = _poll_task_ok(proxmox, node, upid, timeout=330)
        except Exception:
            pass

    # 3 — force stop
    if not stopped:
        print("  Graceful shutdown timed out — forcing stop to apply pending changes.",
              file=sys.stderr)
        upid = proxmox.nodes(node).qemu(vmid).status.stop.post()
        if upid:
            wait_task(proxmox, node, upid)

    upid = proxmox.nodes(node).qemu(vmid).status.start.post()
    if upid:
        wait_task(proxmox, node, upid)


# ── VM name resolution ────────────────────────────────────────────────────────

def _pick_pve_name(vm_name: str, info: Dict[str, Any]) -> str:
    """Apply the display-name priority to a {fqdn, host} pair from the NixOS config.

    Priority:
      1. networking.fqdn (if it contains a dot, i.e. has a domain)
      2. networking.hostName
      3. Last segment of vm_name (directory name)
    """
    fqdn = info.get("fqdn")
    if fqdn and "." in fqdn and fqdn not in ("nixos",):
        return fqdn
    host = info.get("host")
    if host and host not in ("", "nixos"):
        return host
    return vm_name.split(".")[-1]


def _hosts_fingerprint(flake_root: str) -> str:
    """Cheap content key for the host network configs, to invalidate the name cache.

    Scoped to `hosts/` and `flake.lock` (the committed tree objects plus any
    uncommitted changes to them) so unrelated edits — e.g. to this tool — don't
    needlessly bust the cache. hostName/fqdn live under hosts/<h>/; if a shared
    module ever drives them, a stale cached name is the only fallout (a wrong
    display name), and any commit/edit under hosts/ refreshes it.
    """
    import hashlib

    def _git(*args: str) -> str:
        try:
            return subprocess.run(
                ["git", *args], cwd=flake_root,
                capture_output=True, text=True,
            ).stdout
        except Exception:
            return ""

    parts = [
        _git("rev-parse", "HEAD:hosts").strip(),        # committed hosts/ tree
        _git("rev-parse", "HEAD:flake.lock").strip(),   # committed flake inputs
        _git("status", "--porcelain", "--", "hosts", "flake.lock"),  # dirty bits
    ]
    if not any(parts):
        # Not a git repo (FLAKE_ROOT fell back to $PWD) — recompute each run
        # rather than risk reusing another tree's cache.
        return f"nogit-{os.getpid()}"
    return hashlib.sha256("\0".join(parts).encode()).hexdigest()[:16]


def _name_cache_path(fingerprint: str) -> pathlib.Path:
    base = pathlib.Path(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")))
    return base / "proxmox-sync" / f"names-{fingerprint}.json"


# Process-level memo so a single run never re-evaluates a host name.
_NAME_MEMO: Dict[str, str] = {}


def _eval_host_names(names: List[str], flake_root: str) -> Dict[str, Dict[str, Any]]:
    """Evaluate networking.fqdn/hostName for many hosts in a SINGLE nix process.

    A separate `nix eval` per host re-evaluates nixpkgs every time (~2.5s each);
    one batched eval over all needed hosts amortises that to a fraction per host.
    """
    if not names:
        return {}
    name_list = "[" + " ".join('"' + n.replace('"', '\\"') + '"' for n in names) + "]"
    # Reference the flake by absolute path via getFlake (like nix_eval_proxmox),
    # not '.#…': the latter resolves relative to the process cwd and silently
    # fails to find the flake when the tool is launched from outside the repo,
    # which made every host fall back to its directory name.
    expr = (
        "let f = builtins.getFlake (toString " + json.dumps(flake_root) + "); "
        "cfgs = f.nixosConfigurations; names = " + name_list + "; in "
        "builtins.listToAttrs (builtins.concatMap (n: "
        "if builtins.hasAttr n cfgs then [{ name = n; value = { "
        "fqdn = cfgs.${n}.config.networking.fqdn or null; "
        "host = cfgs.${n}.config.networking.hostName or null; }; }] "
        "else []) names)"
    )
    try:
        r = subprocess.run(
            ["nix", "eval", "--json", "--impure", "--expr", expr],
            cwd=flake_root, capture_output=True, text=True, check=True,
        )
        return json.loads(r.stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return {}


def resolve_pve_names(names: List[str], flake_root: str) -> Dict[str, str]:
    """Resolve PVE display names for many hosts at once, cached on disk.

    Falls back to the last vm_name segment for any host that fails to evaluate.
    """
    names = list(dict.fromkeys(names))  # de-dupe, preserve order
    result: Dict[str, str] = {}
    missing = [n for n in names if n not in _NAME_MEMO]

    if missing:
        path = _name_cache_path(_hosts_fingerprint(flake_root))
        disk: Dict[str, str] = {}
        if path.exists():
            try:
                disk = json.loads(path.read_text())
            except Exception:
                disk = {}
        for n in missing:
            if n in disk:
                _NAME_MEMO[n] = disk[n]
        still_missing = [n for n in missing if n not in _NAME_MEMO]
        if still_missing:
            raw = _eval_host_names(still_missing, flake_root)
            for n in still_missing:
                if n in raw:
                    _NAME_MEMO[n] = _pick_pve_name(n, raw[n] or {})
                    disk[n] = _NAME_MEMO[n]
                # Hosts missing from `raw` failed to evaluate; leave them out of
                # the memo and cache so the dir-name fallback below applies for
                # this run only — a transient eval failure must not poison the
                # on-disk cache until the next hosts-fingerprint change.
            if any(n in raw for n in still_missing):
                try:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(json.dumps(disk))
                except Exception:
                    pass

    for n in names:
        result[n] = _NAME_MEMO.get(n, n.split(".")[-1])
    return result


# ── Flake evaluation ───────────────────────────────────────────────────────────

def nix_eval(flake_root: str, attr: str) -> Any:
    try:
        r = subprocess.run(
            ["nix", "eval", "--json", f".#{attr}"],
            cwd=flake_root,
            capture_output=True,
            text=True,
            check=True,
        )
        return json.loads(r.stdout)
    except subprocess.CalledProcessError as e:
        fail(f"nix eval .#{attr} failed:\n{e.stderr.strip()}")
    except json.JSONDecodeError as e:
        fail(f"nix eval .#{attr} returned invalid JSON: {e}")


def nix_eval_proxmox(flake_root: str) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    """Evaluate proxmoxNodes and proxmoxVMs in a single nix process.

    Two `nix eval .#attr` calls pay the ~2.5s nix/nixpkgs startup twice; folding
    them into one `getFlake` expr halves that fixed cost.
    """
    expr = (
        "let f = builtins.getFlake (toString " + json.dumps(flake_root) + "); "
        "in { nodes = f.proxmoxNodes; vms = f.proxmoxVMs; }"
    )
    try:
        r = subprocess.run(
            ["nix", "eval", "--json", "--impure", "--expr", expr],
            cwd=flake_root, capture_output=True, text=True, check=True,
        )
        out = json.loads(r.stdout)
        return out["nodes"], out["vms"]
    except subprocess.CalledProcessError as e:
        fail(f"nix eval (proxmoxNodes/proxmoxVMs) failed:\n{e.stderr.strip()}")
    except (json.JSONDecodeError, KeyError) as e:
        fail(f"nix eval (proxmoxNodes/proxmoxVMs) returned invalid JSON: {e}")


# ── Nix serialisation (for `import`) ──────────────────────────────────────────

# Fields that are auto-generated by PVE and should never appear in a desired-state file.
# digest:   internal hash for optimistic concurrency — changes on every write.
# meta:     creation metadata (qemu version, ctime) — auto-set.
# smbios1:  SMBIOS UUID auto-generated per VM — setting it is rarely intentional.
# vmgenid:  VM generation ID — changes on every restore/clone, read-only in practice.
_PVE_SKIP_FIELDS = {"digest", "meta", "smbios1", "vmgenid"}

# Fields PVE returns as numeric strings but are really integers in the API.
_INT_FIELDS = {
    "agent", "balloon", "cores", "memory", "numa",
    "onboot", "shares", "sockets", "vcpus",
}


def _coerce_pve(field: str, value: Any) -> Any:
    """Coerce a PVE API value to a more natural Python type.

    Pure-numeric strings in known integer fields are returned as int.
    """
    if isinstance(value, str) and value.isdigit():
        if field in _INT_FIELDS:
            return int(value)
    return value


def _nix_val(v: Any) -> str:
    """Serialise a Python value as a Nix literal."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if v is None:
        return "null"
    s = str(v)
    if "\n" in s:
        escaped = s.replace("''", "'''")
        return f"''\n    {escaped}\n  ''"
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _render_proxmox_nix(vmid: int, inv_name: str, cfg: Dict[str, Any]) -> str:
    """Return a proxmox.nix Nix expression for the given PVE config dict."""
    lines = ["{"]
    lines.append(f"  vmid = {vmid};")
    lines.append(f'  node = "{inv_name}";')
    lines.append("")
    for k in sorted(cfg):
        if k == "vmid":
            continue
        lines.append(f"  {k} = {_nix_val(cfg[k])};")
    lines.append("}")
    return "\n".join(lines) + "\n"


# ── Import command ─────────────────────────────────────────────────────────────

def cmd_import(args: argparse.Namespace, root: str, repo: pathlib.Path) -> None:
    nodes: Dict[str, Any] = nix_eval(root, "proxmoxNodes")

    inv_name: str = args.node
    if inv_name not in nodes:
        fail(f"Node '{inv_name}' not in proxmoxNodes. Available: {list(nodes)}")

    node_cfg = nodes[inv_name]
    env = load_env_file(node_cfg["envFile"])
    prox = connect(node_cfg["url"], env, args.verify_ssl)
    pve_node = resolve_pve_node(prox, node_cfg)

    vmid: int = args.vmid
    try:
        raw = prox.nodes(pve_node).qemu(vmid).config.get()
    except Exception as e:
        fail(f"Failed to read vmid {vmid} from {inv_name}: {e}")

    # Strip internal PVE fields; URL-decode sshkeys; coerce numeric strings.
    cfg: Dict[str, Any] = {}
    for k, v in raw.items():
        if k in _PVE_SKIP_FIELDS:
            continue
        if k == "sshkeys":
            v = urllib.parse.unquote(str(v))
        else:
            v = _coerce_pve(k, v)
        cfg[k] = v

    # Stamp the managed tag so sync --prune recognises this VM as owned.
    managed_tag: str = args.managed_tag
    current_tags = str(cfg.get("tags") or "")
    new_tags = merge_managed_tag(current_tags, managed_tag)
    if new_tags != current_tags:
        try:
            prox.nodes(pve_node).qemu(vmid).config.put(tags=new_tags)
            print(f"Tagged   vmid {vmid} with '{managed_tag}' in PVE.")
        except Exception as e:
            print(f"  WARN: could not apply managed tag in PVE: {e}", file=sys.stderr)
    cfg["tags"] = new_tags

    host_key: str = args.host  # dotted path: server.home.myhost
    dest = repo / "hosts" / pathlib.Path(*host_key.split(".")) / "proxmox.nix"

    if dest.exists() and not args.force:
        fail(f"{dest} already exists. Use --force to overwrite.")

    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(_render_proxmox_nix(vmid, inv_name, cfg))
    print(f"Wrote {dest.relative_to(repo)}")
    print(f"  vmid={vmid}  node={inv_name}  name={cfg.get('name', '?')}")
    print("Review the file and remove any fields you don't want proxmox-sync to manage.")


# ── Interactive import command ─────────────────────────────────────────────────

def _do_import_vm(
    prox: "ProxmoxAPI",
    pve_node: str,
    vmid: int,
    inv_name: str,
    host_key: str,
    managed_tag: str,
    repo: pathlib.Path,
    root: str,
    verify_ssl: bool,
    force: bool,
) -> bool:
    """Import a single VM; returns True on success."""
    try:
        raw = prox.nodes(pve_node).qemu(vmid).config.get()
    except Exception as e:
        print(f"  ERROR reading config: {e}", file=sys.stderr)
        return False

    cfg: Dict[str, Any] = {}
    for k, v in raw.items():
        if k in _PVE_SKIP_FIELDS:
            continue
        if k == "sshkeys":
            v = urllib.parse.unquote(str(v))
        else:
            v = _coerce_pve(k, v)
        cfg[k] = v

    current_tags = str(cfg.get("tags") or "")
    new_tags = merge_managed_tag(current_tags, managed_tag)
    if new_tags != current_tags:
        try:
            prox.nodes(pve_node).qemu(vmid).config.put(tags=new_tags)
        except Exception as e:
            print(f"  WARN: could not apply managed tag in PVE: {e}", file=sys.stderr)
    cfg["tags"] = new_tags

    dest = repo / "hosts" / pathlib.Path(*host_key.split(".")) / "proxmox.nix"
    if dest.exists() and not force:
        print(f"  SKIP: {dest.relative_to(repo)} already exists (pass --force to overwrite).")
        return False

    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(_render_proxmox_nix(vmid, inv_name, cfg))
    print(f"  Wrote {dest.relative_to(repo)}")
    return True


# ── Host discovery ─────────────────────────────────────────────────────────────

def _existing_host_keys(repo: pathlib.Path) -> List[str]:
    """Return sorted dotted host keys for every existing host in the repo.

    A host leaf is any directory containing a meta.json; its path relative to
    hosts/ is the dotted host key. E.g. hosts/server/home/newFortress/meta.json
    → 'server.home.newFortress'. These are the real directories a VM can be
    mapped onto — nothing is invented.
    """
    hosts_dir = repo / "hosts"
    keys: set = set()
    if not hosts_dir.is_dir():
        return []
    for meta in hosts_dir.rglob("meta.json"):
        rel = meta.parent.relative_to(hosts_dir)
        if rel.parts:
            keys.add(".".join(rel.parts))
    return sorted(keys)


# ── Fuzzy finder (prompt_toolkit) ──────────────────────────────────────────────

def _fuzzy_score(query: str, candidate: str) -> Optional[int]:
    """Case-insensitive subsequence fuzzy match over the whole string.

    Returns a score (higher = better) on match, or None when `query` is not a
    subsequence of `candidate`. Unlike prompt_toolkit's FuzzyWordCompleter this
    matches against the entire candidate, so dotted queries like 'server.home'
    work correctly.
    """
    q, c = query.lower(), candidate.lower()
    if not q:
        return 0
    score = 0
    ci = 0
    prev = -1
    for qch in q:
        while ci < len(c) and c[ci] != qch:
            ci += 1
        if ci >= len(c):
            return None
        if ci == prev + 1:
            score += 3                       # consecutive-run bonus
        if ci == 0 or c[ci - 1] in "._- ":
            score += 2                       # word-boundary bonus
        score += 1
        prev = ci
        ci += 1
    score -= len(c) // 16                     # mild preference for shorter
    return score


def _fuzzy_select(
    header: str,
    candidates: List[str],
    initial: str = "",
) -> Optional[str]:
    """
    Fuzzy-select a value from `candidates` using prompt_toolkit.

    The completion menu is open from the start showing every candidate; typing
    fuzzy-filters it, ↑/↓ pick, Enter confirms. Free-typed values are accepted
    even when nothing matches (manual entry).

    Keys: Enter confirms, Esc skips this VM (returns None), Ctrl-C aborts the
    whole program (KeyboardInterrupt propagates). Returns the chosen string, or
    None when skipped / left empty.

    `initial` is offered as the bottom-toolbar hint only — it is NOT inserted as
    editable text, so typing a filter does not get appended to it.

    Falls back to a plain input() prompt when stdin/stdout is not a TTY.
    """
    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        # Ctrl-C still raises KeyboardInterrupt here (aborts the program).
        raw = input(f"  {header}\n  host key [{initial}] (empty to skip): ").strip()
        return raw or None

    from prompt_toolkit import prompt as ptk_prompt
    from prompt_toolkit.application import get_app
    from prompt_toolkit.completion import Completer, Completion
    from prompt_toolkit.formatted_text import HTML
    from prompt_toolkit.key_binding import KeyBindings

    class _HostFuzzyCompleter(Completer):
        """Rank candidates by subsequence fuzzy score over the entire line."""

        def __init__(self, items: List[str]) -> None:
            self.items = items

        def get_completions(self, document, complete_event):
            text = document.text_before_cursor
            scored = [
                (s, c) for c in self.items
                for s in [_fuzzy_score(text, c)] if s is not None
            ]
            scored.sort(key=lambda x: -x[0])
            for _, cand in scored:
                # Replace the whole typed line with the chosen candidate.
                yield Completion(cand, start_position=-len(text))

    completer = _HostFuzzyCompleter(candidates)

    def _open_menu() -> None:
        # Pre-open the completion menu so all candidates are visible immediately.
        get_app().current_buffer.start_completion(select_first=False)

    # Esc skips this VM. A lone Escape is distinguished from arrow-key escape
    # sequences by prompt_toolkit's parser, so navigation still works.
    _SKIP = object()
    kb = KeyBindings()

    @kb.add("escape")
    def _(event):
        event.app.exit(result=_SKIP)

    hint = initial or "type a host key"
    # Ctrl-C raises KeyboardInterrupt here and is intentionally NOT caught — it
    # propagates up to abort the whole import run.
    result = ptk_prompt(
        HTML("  <ansicyan>❯</ansicyan> "),
        completer=completer,
        complete_while_typing=True,
        pre_run=_open_menu,
        key_bindings=kb,
        bottom_toolbar=HTML(
            f" {header}  ·  hint: <b>{hint}</b>  ·  ↑↓ pick · Enter ok · Esc skip · Ctrl-C quit"
        ),
        reserve_space_for_menu=8,
    )
    if result is _SKIP:
        return None
    result = (result or "").strip()
    return result or None


def cmd_import_interactive(args: argparse.Namespace, root: str, repo: pathlib.Path) -> None:
    nodes: Dict[str, Any] = nix_eval(root, "proxmoxNodes")

    # Pick node interactively if not given.
    inv_name: str = args.node
    if not inv_name:
        node_names = sorted(nodes)
        if len(node_names) == 1:
            inv_name = node_names[0]
        else:
            print("Available nodes:")
            for i, n in enumerate(node_names, 1):
                print(f"  {i}) {n}  ({nodes[n]['url']})")
            while True:
                raw = input("Select node [1]: ").strip() or "1"
                try:
                    inv_name = node_names[int(raw) - 1]
                    break
                except (ValueError, IndexError):
                    print("  Invalid selection.")

    if inv_name not in nodes:
        fail(f"Node '{inv_name}' not in proxmoxNodes. Available: {list(nodes)}")

    node_cfg = nodes[inv_name]
    managed_tag: str = args.managed_tag

    print(f"\n=== Interactive import — {inv_name} ({node_cfg['url']}) ===\n")

    env = load_env_file(node_cfg["envFile"])
    prox = connect(node_cfg["url"], env, args.verify_ssl)
    pve_node = resolve_pve_node(prox, node_cfg)

    print("Fetching VM list…")
    try:
        vm_list = sorted(prox.nodes(pve_node).qemu.get(), key=lambda v: int(v["vmid"]))
    except Exception as e:
        fail(f"Failed to list VMs: {e}")

    # Build a map of vmid → host_key for already-managed VMs.
    print("Evaluating flake…")
    try:
        all_vms: Dict[str, Any] = nix_eval(root, "proxmoxVMs")
    except SystemExit:
        all_vms = {}
    managed: Dict[int, str] = {
        cfg["vmid"]: name
        for name, cfg in all_vms.items()
        if cfg.get("node") == inv_name and cfg.get("vmid") is not None
    }

    # Print overview table.
    print()
    rows = []
    for vm in vm_list:
        vmid = int(vm["vmid"])
        name = vm.get("name", "?")
        status = vm.get("status", "?")
        tags = str(vm.get("tags") or "")
        if vmid in managed:
            mark = f"✓  already → {managed[vmid]}"
        elif has_managed_tag(tags, managed_tag):
            mark = f"⚠  has '{managed_tag}' tag but no proxmox.nix"
        else:
            mark = "✗  unmanaged"
        rows.append({"VMID": str(vmid), "NAME": name, "STATUS": status, "MANAGED": mark})
    for line in _table(rows, ["VMID", "NAME", "STATUS", "MANAGED"]):
        print(f"  {line}")

    unmanaged = [vm for vm in vm_list if int(vm["vmid"]) not in managed]
    if not unmanaged:
        print("\nAll VMs on this node are already managed. Nothing to do.")
        return

    # Candidates are the real existing host directories — nothing invented.
    existing_hosts = _existing_host_keys(repo)
    if not existing_hosts:
        print("  (no host directories found under hosts/ — type host keys manually)")

    print(f"\n{len(unmanaged)} unmanaged VM(s) — fuzzy-select an existing host for each.\n")

    imported = 0
    skipped  = 0
    try:
        for vm in unmanaged:
            vmid     = int(vm["vmid"])
            pve_name = vm.get("name", "?")
            status   = vm.get("status", "?")
            tags     = str(vm.get("tags") or "")
            tag_hint = f"  tags: {tags}" if tags else ""

            slug = re.sub(r"[^a-zA-Z0-9_-]", "", pve_name) or f"vm{vmid}"

            print(f"[{vmid}] '{pve_name}' [{status}]{tag_hint}")

            host_key = _fuzzy_select(
                header=f"vmid {vmid} '{pve_name}' → existing host (or type a new key)",
                candidates=existing_hosts,
                initial=slug,
            )

            if not host_key:
                print("  Skipped.")
                skipped += 1
            elif " " in host_key or "/" in host_key or "." not in host_key:
                print(f"  Invalid host key {host_key!r} — must be dot-separated with no spaces. Skipped.")
                skipped += 1
            else:
                print(f"  → {host_key}")
                ok = _do_import_vm(
                    prox, pve_node, vmid, inv_name, host_key,
                    managed_tag, repo, root, args.verify_ssl, args.force,
                )
                if ok:
                    imported += 1
            print()
    except KeyboardInterrupt:
        print(f"\nAborted — {imported} imported, {skipped} skipped.")
        sys.exit(130)

    print(f"Done — {imported} imported, {skipped} skipped.")


# ── Setup-token command ────────────────────────────────────────────────────────

def cmd_setup_token(args: argparse.Namespace, root: str, repo: pathlib.Path) -> None:
    """Create a least-privilege role + API token for proxmox-sync on one node."""
    import getpass

    nodes: Dict[str, Any] = nix_eval(root, "proxmoxNodes")
    inv_name: str = args.node
    if inv_name not in nodes:
        fail(f"Node '{inv_name}' not in proxmoxNodes. Available: {list(nodes)}")

    node_cfg = nodes[inv_name]
    env_path = os.path.expanduser(node_cfg["envFile"])

    print(f"Enter admin credentials to connect to {node_cfg['url']}:")
    default_user = "root@pam"
    user_input = input(f"  Username [{default_user}]: ").strip() or default_user
    admin_env: Dict[str, str] = {
        "PROXMOX_USER": user_input,
        "PROXMOX_PASSWORD": getpass.getpass("  Password: "),
    }

    prox = connect(node_cfg["url"], admin_env, args.verify_ssl)

    role_name: str = args.role_name
    user_id: str = args.user        # e.g. "proxmox-sync@pve"
    token_name: str = args.token_name
    full_token_id = f"{user_id}!{token_name}"
    privs_str = ",".join(sorted(SYNC_PRIVS))
    rotate: bool = args.rotate

    if not rotate:
        # ── Role ──────────────────────────────────────────────────────────────
        existing_roles = {r["roleid"] for r in prox.access.roles.get()}
        if role_name in existing_roles:
            prox.access.roles(role_name).put(privs=privs_str)
            print(f"Updated  role '{role_name}' ({len(SYNC_PRIVS)} privs).")
        else:
            prox.access.roles.post(roleid=role_name, privs=privs_str)
            print(f"Created  role '{role_name}' ({len(SYNC_PRIVS)} privs).")

        # ── User ──────────────────────────────────────────────────────────────
        existing_users = {u["userid"] for u in prox.access.users.get()}
        if user_id not in existing_users:
            if not args.create_user:
                fail(
                    f"User '{user_id}' does not exist. "
                    "Pass --create-user to create it automatically."
                )
            realm = user_id.split("@")[-1] if "@" in user_id else "pve"
            if realm != "pve":
                fail(
                    f"Can only auto-create users in the 'pve' realm; "
                    f"'{user_id}' is in '{realm}'."
                )
            prox.access.users.post(
                userid=user_id,
                comment="proxmox-sync service account (created by proxmox-sync setup-token)",
            )
            print(f"Created  user '{user_id}'.")
        else:
            print(f"User     '{user_id}' already exists.")

    # ── Token ─────────────────────────────────────────────────────────────────
    # PVE API path is /access/users/{userid}/token/{tokenid} (singular).
    try:
        existing_tokens = {t["tokenid"] for t in (prox.access.users(user_id).token.get() or [])}
    except Exception:
        existing_tokens = set()
    if token_name in existing_tokens:
        if not rotate and not args.force:
            fail(
                f"Token '{full_token_id}' already exists "
                "(the secret cannot be retrieved again). "
                "Delete it in PVE first, pass --force, or use --rotate."
            )
        prox.access.users(user_id).token(token_name).delete()
        print(f"Deleted  existing token '{full_token_id}'.")
    elif rotate:
        fail(f"Token '{full_token_id}' does not exist — nothing to rotate. Run setup-token without --rotate first.")

    result = prox.access.users(user_id).token(token_name).post(
        comment="proxmox-sync (created by proxmox-sync setup-token)",
        privsep=0,  # token inherits the user's ACL privileges
    )
    if not isinstance(result, dict) or "value" not in result:
        fail(f"Token created but secret not returned by API (got: {result!r}). "
             "Check the PVE web UI to copy the secret manually.")
    token_secret: str = result["value"] or ""
    if not token_secret:
        fail("Token created but API returned an empty secret. "
             "Check the PVE web UI to copy the secret manually.")
    print(f"Created  token '{full_token_id}'.")

    if not rotate:
        # ── ACL ───────────────────────────────────────────────────────────────
        prox.access.acl.put(
            path="/",
            roles=role_name,
            users=user_id,
            propagate=1,
        )
        print(f"Set ACL  '{role_name}' on / for '{user_id}' (propagate=1).")

    # ── Write env file ────────────────────────────────────────────────────────
    env_dir = os.path.dirname(env_path)
    if env_dir:
        os.makedirs(env_dir, mode=0o700, exist_ok=True)
    lines = [
        f"PROXMOX_TOKEN_ID={full_token_id}\n",
        f"PROXMOX_TOKEN_SECRET={token_secret}\n",
    ]
    with open(env_path, "w") as fh:
        os.chmod(fh.fileno(), 0o600)
        fh.writelines(lines)
    print(f"\nWrote credentials to {env_path} (mode 600).")


# ── Status command ────────────────────────────────────────────────────────────

def _table(rows: List[Dict[str, str]], cols: List[str]) -> List[str]:
    widths = {c: len(c) for c in cols}
    for row in rows:
        for c in cols:
            widths[c] = max(widths[c], len(row.get(c, "")))
    header = "  ".join(c.ljust(widths[c]) for c in cols)
    sep    = "  ".join("─" * widths[c] for c in cols)
    lines  = [header, sep]
    for row in rows:
        lines.append("  ".join(row.get(c, "").ljust(widths[c]) for c in cols))
    return lines


def cmd_status(args: argparse.Namespace, root: str, repo: pathlib.Path) -> None:
    ig_files = [repo / ".proxmoxignore", repo / "proxmox" / ".proxmoxignore"]
    rules = load_ignore_rules([], ig_files)

    print("Evaluating flake...")
    nodes, all_vms = nix_eval_proxmox(root)

    if args.node:
        if args.node not in nodes:
            fail(f"Node '{args.node}' not in proxmoxNodes. Available: {list(nodes)}")
        nodes = {args.node: nodes[args.node]}

    for inv_name, node_cfg in sorted(nodes.items()):
        print(f"\n=== {inv_name} ({node_cfg['url']}) ===")

        env = load_env_file(node_cfg["envFile"])
        try:
            prox = connect(node_cfg["url"], env, args.verify_ssl)
            pve_node = resolve_pve_node(prox, node_cfg)
        except Exception as e:
            print(f"  ERROR connecting: {e}", file=sys.stderr)
            continue

        try:
            live_list = prox.nodes(pve_node).qemu.get()
        except Exception as e:
            print(f"  ERROR listing VMs: {e}", file=sys.stderr)
            continue

        # PVE templates (the golden images VMs are cloned from) are not deployable
        # VMs — drop them so they never show up as "unmanaged".
        live: Dict[int, Dict] = {
            int(vm["vmid"]): vm for vm in live_list if not _is_template(vm)
        }

        desired = {
            name: cfg
            for name, cfg in all_vms.items()
            if cfg.get("node") == inv_name
        }
        desired_ids = {cfg["vmid"] for cfg in desired.values() if cfg.get("vmid") is not None}

        managed_tag: str = args.managed_tag
        rows: List[Dict[str, str]] = []

        # VMs a `sync` run would act on, surfaced in a dedicated section below.
        # to_create: declared in a proxmox.nix but not present on the node yet.
        # to_update: present but drifted — carries the list of fields that differ.
        to_create: List[Tuple[str, str]] = []          # (vmid_or_?, vm_name)
        to_update: List[Tuple[str, str, List[str]]] = []  # (vmid, vm_name, fields)

        # vmid may be None (not yet assigned), so coalesce to 0 for ordering
        # rather than comparing None to int.
        ordered = sorted(desired.items(), key=lambda kv: kv[1].get("vmid") or 0)
        live_managed = [(n, c) for n, c in ordered if c.get("vmid") in live]

        # Resolve every display name we need in one batched, cached nix eval
        # instead of a separate `nix eval` per VM (the dominant cost).
        name_map = resolve_pve_names(
            [n for n, c in live_managed if "name" not in c], root
        )

        # Fetch each live VM's config (and pending changes) concurrently — these
        # are independent network round-trips, so they parallelise cleanly.
        def _fetch(item: Tuple[str, Dict]) -> Tuple[str, Optional[Dict], List, Optional[Exception]]:
            name, cfg = item
            vmid = cfg["vmid"]
            try:
                cur_cfg = prox.nodes(pve_node).qemu(vmid).config.get()
                running = live[vmid].get("status", "?") == "running"
                pending = get_pending_changes(prox, pve_node, vmid) if running else []
                return name, cur_cfg, pending, None
            except Exception as e:  # noqa: BLE001 — surfaced per-VM as a read failure
                return name, None, [], e

        fetched: Dict[str, Tuple[Optional[Dict], List, Optional[Exception]]] = {}
        if live_managed:
            with concurrent.futures.ThreadPoolExecutor(
                max_workers=min(8, len(live_managed))
            ) as ex:
                for name, cur_cfg, pending, err in ex.map(_fetch, live_managed):
                    fetched[name] = (cur_cfg, pending, err)

        for vm_name, vm_cfg in ordered:
            vmid = vm_cfg.get("vmid")
            if vmid is None:
                rows.append({"VMID": "?", "NAME": vm_name, "STATE": "—", "SYNC": "✗ vmid not assigned"})
                to_create.append(("?", vm_name))
                continue

            if vmid not in live:
                rows.append({"VMID": str(vmid), "NAME": vm_name, "STATE": "—", "SYNC": "✗ not created"})
                to_create.append((str(vmid), vm_name))
                continue

            state = live[vmid].get("status", "?")

            api_cfg = {k: v for k, v in vm_cfg.items() if k not in TOOL_FIELDS}
            if "name" not in api_cfg:
                api_cfg["name"] = name_map.get(vm_name, vm_name.split(".")[-1])

            cur_cfg, pending, err = fetched.get(vm_name, (None, [], None))
            if err is not None or cur_cfg is None:
                sync_str = "? (config read failed)"
            else:
                delta = diff_config(
                    _with_managed_tag(api_cfg, managed_tag), cur_cfg, vm_name, rules
                )
                # Don't flag missing managed tag as drift — sync always re-stamps it.
                if not has_managed_tag(str(cur_cfg.get("tags") or ""), managed_tag):
                    delta.pop("tags", None)
                unused = _get_unused_disks(cur_cfg)
                unused_note = f"  ⚠ {len(unused)} unused disk(s)" if unused else ""
                pend_note = f"  ⏳ {len(pending)} pending reboot" if pending else ""
                sync_str = ("✓ in sync" if not delta else f"~ {len(delta)} field(s) differ") + unused_note + pend_note
                if delta:
                    to_update.append((str(vmid), vm_name, sorted(delta)))

            rows.append({"VMID": str(vmid), "NAME": vm_name, "STATE": state, "SYNC": sync_str})

        # Unmanaged VMs present on node
        unmanaged = [
            vm for vmid, vm in sorted(live.items())
            if vmid not in desired_ids
        ]

        if rows:
            for line in _table(rows, ["VMID", "NAME", "STATE", "SYNC"]):
                print(f"  {line}")

        if unmanaged:
            print(f"\n  Unmanaged VMs (no proxmox.nix):")
            for vm in unmanaged:
                tag_marker = f"  [{managed_tag}]" if has_managed_tag(str(vm.get("tags") or ""), managed_tag) else ""
                print(f"    {vm['vmid']:>6}  {vm.get('name', '?'):<24}  {vm.get('status', '?')}{tag_marker}")

        # What `proxmox-sync sync` would actually deploy on this node.
        if to_create or to_update:
            print("\n  ▸ To be deployed (run `proxmox-sync sync`):")
            for vmid, vm_name in to_create:
                print(f"    + create  {vmid:>6}  {vm_name}")
            for vmid, vm_name, fields in to_update:
                joined = ", ".join(fields)
                print(f"    ~ update  {vmid:>6}  {vm_name}  ({joined})")

        n_ok      = sum(1 for r in rows if r["SYNC"].startswith("✓"))
        n_drift   = len(to_update)
        n_missing = len(to_create)
        print(
            f"\n  {len(rows)} desired  "
            f"({n_ok} in sync, {n_drift} drifted, {n_missing} missing)  "
            f"|  {n_missing + n_drift} to deploy  |  {len(unmanaged)} unmanaged"
        )


# ── Destroy command ────────────────────────────────────────────────────────────

def cmd_destroy(args: argparse.Namespace, root: str, repo: pathlib.Path) -> None:
    host_key: str = args.host

    print("Evaluating flake...")
    nodes: Dict[str, Any] = nix_eval(root, "proxmoxNodes")
    all_vms: Dict[str, Any] = nix_eval(root, "proxmoxVMs")

    if host_key not in all_vms:
        fail(
            f"'{host_key}' not found in proxmoxVMs. "
            "Make sure a proxmox.nix exists and is git-tracked."
        )

    vm_cfg = all_vms[host_key]
    vmid: Optional[int] = vm_cfg.get("vmid")
    inv_name: Optional[str] = vm_cfg.get("node")

    if not vmid:
        fail(f"proxmox.nix for '{host_key}' has no vmid — nothing to destroy.")
    if not inv_name or inv_name not in nodes:
        fail(f"proxmox.nix for '{host_key}' has node={inv_name!r} which is not in proxmoxNodes.")

    node_cfg = nodes[inv_name]
    env = load_env_file(node_cfg["envFile"])
    prox = connect(node_cfg["url"], env, args.verify_ssl)
    pve_node = resolve_pve_node(prox, node_cfg)

    try:
        vm_list = {int(vm["vmid"]): vm for vm in prox.nodes(pve_node).qemu.get()}
    except Exception as e:
        fail(f"Failed to list VMs: {e}")

    if vmid not in vm_list:
        print(f"VM {vmid} ({host_key}) is not present on {inv_name} — nothing to do.")
        return

    vm_info = vm_list[vmid]
    vm_tags = str(vm_info.get("tags") or "")
    if not has_managed_tag(vm_tags, args.managed_tag):
        fail(
            f"VM {vmid} '{vm_info.get('name', '?')}' does not carry the managed tag "
            f"'{args.managed_tag}'. Refusing to delete an unowned VM. "
            "Add the tag manually in PVE if you're sure."
        )

    label = f"vmid {vmid}  '{vm_info.get('name', '?')}'  [{vm_info.get('status', '?')}]  on {inv_name}"
    print(f"  Target: {label}")

    if not args.force and not _confirm(f"  Really delete {label}?"):
        print("  Aborted.")
        return

    # Snapshot config before destroying. Fail closed — never delete without a record.
    try:
        cur_cfg = prox.nodes(pve_node).qemu(vmid).config.get()
        bpath = backup_vm_config(root, pve_node, vmid, str(vm_info.get("name") or host_key), cur_cfg)
        print(f"  Backed up config → {os.path.relpath(bpath, root)}")
    except Exception as e:
        fail(f"Failed to back up config before destroy: {e}")

    if vm_info.get("status", "stopped") != "stopped":
        print(f"  Stopping VM {vmid}…")
        upid = prox.nodes(pve_node).qemu(vmid).status.stop.post()
        wait_task(prox, pve_node, upid)

    print(f"  Deleting VM {vmid}…")
    upid = prox.nodes(pve_node).qemu(vmid).delete()
    if upid:
        wait_task(prox, pve_node, upid)
    print(f"  Deleted.")


# ── Sync command ───────────────────────────────────────────────────────────────

def cmd_sync(args: argparse.Namespace, root: str, repo: pathlib.Path) -> None:
    managed_tag: str = args.managed_tag

    ig_files: List[pathlib.Path]
    if args.ignore_file:
        if not args.ignore_file.exists():
            fail(f"ignore file not found: {args.ignore_file}")
        ig_files = [args.ignore_file]
    else:
        ig_files = [repo / ".proxmoxignore", repo / "proxmox" / ".proxmoxignore"]
    rules = load_ignore_rules(args.ignore, ig_files)

    print("Evaluating flake...")
    nodes, all_vms = nix_eval_proxmox(root)
    print(f"  {len(nodes)} node(s), {len(all_vms)} VM definition(s)")

    if args.node:
        if args.node not in nodes:
            fail(f"Node '{args.node}' not in proxmoxNodes. Available: {list(nodes)}")
        nodes = {args.node: nodes[args.node]}

    if args.dry_run:
        print("  (dry run — no changes will be applied)")

    total_changes = 0

    for inv_name, node_cfg in sorted(nodes.items()):
        print(f"\n=== {inv_name} ({node_cfg['url']}) ===")

        env = load_env_file(node_cfg["envFile"])
        try:
            prox = connect(node_cfg["url"], env, args.verify_ssl)
            pve_node = resolve_pve_node(prox, node_cfg)
        except SystemExit:
            raise
        except Exception as e:
            print(f"  ERROR connecting: {e}", file=sys.stderr)
            continue

        print(f"  Connected  (PVE node: {pve_node})")

        try:
            existing: Dict[int, Dict] = {
                int(vm["vmid"]): vm for vm in prox.nodes(pve_node).qemu.get()
            }
        except Exception as e:
            print(f"  ERROR listing VMs: {e}", file=sys.stderr)
            continue

        desired = {
            name: cfg
            for name, cfg in all_vms.items()
            if cfg.get("node") == inv_name
        }

        # ── Auto-assign vmids ──────────────────────────────────────────────────
        # The vmid is only written back to proxmox.nix once the VM is fully
        # created (see CREATE below), so a failed/rolled-back create doesn't
        # leave a phantom vmid pointing at a VM that doesn't exist.
        freshly_assigned: Dict[str, int] = {}
        reserved_ids: set = set(existing.keys())
        for vm_name, vm_cfg in sorted(desired.items()):
            if vm_cfg.get("vmid") is not None:
                reserved_ids.add(vm_cfg["vmid"])
                continue
            try:
                next_id = int(prox.cluster.nextid.get())
            except (ValueError, TypeError) as e:
                print(f"  ERROR  fetching nextid for {vm_name}: {e}", file=sys.stderr)
                continue
            while next_id in reserved_ids:
                next_id += 1
            reserved_ids.add(next_id)
            vm_cfg["vmid"] = next_id
            freshly_assigned[vm_name] = next_id
            print(f"  Auto-assigned vmid {next_id} to {vm_name}")

        desired_ids = {cfg["vmid"] for cfg in desired.values()}

        print(f"  {len(desired)} VM(s) desired, {len(existing)} present on node")

        # ── Create or update ───────────────────────────────────────────────────

        # One batched, cached name resolution for every VM lacking an explicit
        # name — avoids a per-VM `nix eval` (~2.5s each) inside the loop.
        name_map = resolve_pve_names(
            [n for n, c in desired.items() if "name" not in c], root
        )

        for vm_name, vm_cfg in sorted(desired.items()):
            vmid: int = vm_cfg["vmid"]
            template: Optional[int] = vm_cfg.get("template")

            api_cfg = {k: v for k, v in vm_cfg.items() if k not in TOOL_FIELDS}

            if "name" not in api_cfg:
                api_cfg["name"] = name_map.get(vm_name, vm_name.split(".")[-1])

            if vmid not in existing:
                # ── CREATE ────────────────────────────────────────────────────
                if not template:
                    print(f"  SKIP   {vm_name} (vmid {vmid}): not present and no template defined")
                    continue

                # Prerequisite: a VM we'll colmena-deploy must have
                # deployment.targetHost set in meta.json, else the post-create
                # `colmena apply` has nowhere to connect. Fail before creating
                # anything rather than leaving an undeployable VM behind.
                if not args.no_colmena:
                    host_dir = repo / "hosts" / pathlib.Path(*vm_name.split("."))
                    is_nixos = (host_dir / "configuration.nix").exists() and \
                               (host_dir / "meta.json").exists()
                    if is_nixos and not _colmena_target_host(host_dir):
                        print(
                            f"  ERROR  {vm_name} (vmid {vmid}): deployment.targetHost is "
                            f"unset in meta.json — set it (or pass --no-colmena) before "
                            f"creating. Skipping.",
                            file=sys.stderr,
                        )
                        continue

                print(f"  +CREATE {vm_name} (vmid {vmid})  ← clone template {template}")
                total_changes += 1
                if not args.dry_run:
                    # Clone first; a failure here means nothing was created.
                    try:
                        upid = prox.nodes(pve_node).qemu(template).clone.post(
                            newid=vmid,
                            name=vm_name.split(".")[-1],
                            full=1,
                        )
                        wait_task(prox, pve_node, upid)
                    except Exception as e:
                        print(f"         ERROR cloning: {e}", file=sys.stderr)
                        continue

                    # From here the VM exists — on any failure, offer to roll it back.
                    try:
                        clone_cfg = prox.nodes(pve_node).qemu(vmid).config.get()
                        to_apply = {
                            k: v for k, v in api_cfg.items()
                            if not is_ignored(vm_name, k, rules) and v is not None
                        }
                        to_apply["tags"] = merge_managed_tag(
                            str(to_apply.get("tags") or ""), managed_tag
                        )
                        # Preserve the UUID PVE assigned to the clone when we write smbios1.
                        if "smbios1" in to_apply:
                            uuid = _smbios_uuid(str(clone_cfg.get("smbios1", "")))
                            if uuid:
                                to_apply["smbios1"] = _inject_smbios_uuid(
                                    str(to_apply["smbios1"]), uuid
                                )

                        # Disks: a clone already has the volume, so a spec that omits
                        # one (e.g. 'discard=on,size=80G') borrows the cloned volume,
                        # and any grow is applied through the resize API afterwards.
                        resize_ops: Dict[str, str] = {}
                        for fld in [k for k in to_apply if _DISK_RE.match(k)]:
                            cur_disk = str(clone_cfg.get(fld, ""))
                            new_sz = _disk_size(str(to_apply[fld]))
                            cur_sz = _disk_size(cur_disk)
                            if new_sz:
                                nb = _size_bytes(new_sz)
                                cb = _size_bytes(cur_sz) if cur_sz else None
                                if nb and (cb is None or nb > cb):
                                    resize_ops[fld] = new_sz
                            to_apply[fld] = _disk_put_value(str(to_apply[fld]), cur_disk)

                        prox.nodes(pve_node).qemu(vmid).config.put(**_preprocess_api(to_apply))
                        for disk_fld, sz in sorted(resize_ops.items()):
                            prox.nodes(pve_node).qemu(vmid).resize.put(disk=disk_fld, size=sz)

                        prox.nodes(pve_node).qemu(vmid).status.start.post()
                        print(f"         VM started.")

                        # VM is fully created now — persist an auto-assigned vmid
                        # back to its proxmox.nix so future runs reconcile it.
                        if vm_name in freshly_assigned:
                            write_vmid(repo, vm_name, vmid)
                            print(f"         Wrote vmid {vmid} → {vm_name}/proxmox.nix")

                        if not args.no_colmena:
                            host_dir = repo / "hosts" / pathlib.Path(*vm_name.split("."))
                            is_nixos = (host_dir / "configuration.nix").exists() and \
                                       (host_dir / "meta.json").exists()
                            if not is_nixos:
                                print(f"         No configuration.nix/meta.json — skipping colmena deploy.")
                            else:
                                ip = _extract_ip(str(to_apply.get("ipconfig0", "")))
                                if not ip:
                                    print(
                                        f"         WARN: no ipconfig0 IP found — skipping colmena deploy.",
                                        file=sys.stderr,
                                    )
                                elif not wait_for_ssh(ip):
                                    print(
                                        f"         WARN: SSH timed out on {ip} — skipping colmena deploy.",
                                        file=sys.stderr,
                                    )
                                else:
                                    if not colmena_deploy(root, vm_name, fresh_host=True):
                                        print(
                                            f"         WARN: colmena apply boot failed.",
                                            file=sys.stderr,
                                        )
                                        # The VM was created but never got its config —
                                        # offer to roll it back like any other post-create failure.
                                        _rollback_created_vm(prox, pve_node, vmid, vm_name, args)
                                        continue
                                    else:
                                        # New generation is the boot default; reboot
                                        # to activate it but don't wait for it.
                                        try:
                                            prox.nodes(pve_node).qemu(vmid).status.reboot.post()
                                            print(f"         Rebooting to activate new generation (not waiting).")
                                        except Exception as e:
                                            print(
                                                f"         WARN: could not trigger reboot: {e}",
                                                file=sys.stderr,
                                            )
                        print(f"         done.")
                    except Exception as e:
                        print(f"         ERROR: {e}", file=sys.stderr)
                        _rollback_created_vm(prox, pve_node, vmid, vm_name, args)

            else:
                # ── UPDATE ────────────────────────────────────────────────────
                try:
                    cur_cfg = prox.nodes(pve_node).qemu(vmid).config.get()
                except Exception as e:
                    print(f"  ERROR  reading config for {vm_name}: {e}", file=sys.stderr)
                    continue

                # Fold the managed tag into desired up front so a VM that already
                # carries it isn't reported as drift, and so stamping it (when
                # absent) shows as the real change it is.
                delta = diff_config(
                    _with_managed_tag(api_cfg, managed_tag), cur_cfg, vm_name, rules
                )

                is_running = existing.get(vmid, {}).get("status", "") == "running"

                if not delta:
                    print(f"  ✓      {vm_name} (vmid {vmid})")
                    # Pre-existing pending changes from a previous failed reboot cycle.
                    if is_running and not args.dry_run:
                        pending = get_pending_changes(prox, pve_node, vmid)
                        if pending:
                            pend_keys = sorted(pending)
                            print(f"  PEND   {vm_name}: {len(pending)} field(s) still pending"
                                  f" stop+start from a previous run — {pend_keys}")
                            do_reboot = args.reboot_on_pending or (
                                args.yes or _confirm(
                                    f"  Reboot {vm_name!r} to apply pending changes?"
                                )
                            )
                            if do_reboot:
                                print(f"  Shutting down {vm_name} (graceful)…")
                                try:
                                    shutdown_start_vm(prox, pve_node, vmid)
                                    print(f"  Started.")
                                    total_changes += 1
                                except Exception as e:
                                    print(f"  ERROR during shutdown+start: {e}", file=sys.stderr)
                else:
                    print(f"  ~UPD   {vm_name} (vmid {vmid}):")
                    boot_devices = set(re.findall(r'\w+', str(cur_cfg.get("boot", ""))))
                    for fld in sorted(delta):
                        old = cur_cfg.get(fld, "<unset>")
                        if delta[fld] is None:
                            if _DISK_RE.match(fld):
                                print(f"           -{fld}: {old!r}  (detach → unusedN)")
                                if fld in {"efidisk0", "tpmstate0"}:
                                    print(f"           WARN: detaching {fld} will prevent the VM from booting",
                                          file=sys.stderr)
                                elif fld in boot_devices:
                                    print(f"           WARN: {fld} is in the boot order — VM will not boot after detach",
                                          file=sys.stderr)
                            else:
                                print(f"           -{fld}: {old!r}  (delete)")
                        else:
                            suffix = "  ⚠ requires reboot" if (
                                is_running and (
                                    fld in _REBOOT_REQUIRED_FIELDS or
                                    (_NET_RE.match(fld) and _queues_changed(str(delta[fld]), str(old)))
                                )
                            ) else ""
                            print(f"           {fld}: {old!r}  →  {delta[fld]!r}{suffix}")
                    total_changes += 1
                    if not args.dry_run:
                        # Multiqueue (queues=) changes on a NIC only take effect
                        # after a stop+start. Ask up front, before touching them:
                        # if a reboot isn't wanted, leave those NICs untouched
                        # rather than queue a change that won't apply until the
                        # next manual boot.
                        approved_queue_nets: List[str] = []
                        if is_running:
                            queue_nets = sorted(
                                fld for fld in delta
                                if _NET_RE.match(fld) and delta[fld] is not None
                                and _queues_changed(str(delta[fld]), str(cur_cfg.get(fld, "")))
                            )
                            if queue_nets:
                                print(
                                    f"  Changing queues on {', '.join(queue_nets)} "
                                    f"requires a reboot of {vm_name!r} to take effect."
                                )
                                if args.reboot_on_pending or args.yes or _confirm(
                                    f"  Reboot {vm_name!r} after updating queues?"
                                ):
                                    approved_queue_nets = queue_nets
                                else:
                                    for fld in queue_nets:
                                        print(f"  SKIP   {vm_name}: leaving {fld} queues unchanged (reboot declined)")
                                        delta.pop(fld, None)

                        # Split delta into three buckets:
                        #   detach_disks  — disk set to null → config.put(delete=...) → becomes unusedN
                        #   delete_fields — non-disk null    → config.put(delete=...)
                        #   resize_ops    — disk size change → resize API
                        #   config_delta  — everything else  → config.put
                        detach_disks: List[str] = []
                        delete_fields: List[str] = []
                        resize_ops: Dict[str, str] = {}
                        config_delta: Dict[str, Any] = {}
                        for fld, val in delta.items():
                            if val is None:
                                if _DISK_RE.match(fld):
                                    detach_disks.append(fld)
                                else:
                                    delete_fields.append(fld)
                            elif _DISK_RE.match(fld):
                                cur_disk = str(cur_cfg.get(fld, ""))
                                new_sz = _disk_size(str(val))
                                cur_sz = _disk_size(cur_disk)
                                if new_sz and new_sz != cur_sz:
                                    nb = _size_bytes(new_sz)
                                    cb = _size_bytes(cur_sz) if cur_sz else None
                                    if nb and cb and nb == cb:
                                        pass  # same size, different unit notation — no resize
                                    elif nb and cb and nb < cb:
                                        print(
                                            f"  WARN   {vm_name}: cannot shrink {fld} "
                                            f"from {cur_sz} to {new_sz} — skipping resize",
                                            file=sys.stderr,
                                        )
                                    else:
                                        resize_ops[fld] = new_sz
                                # A spec without its own volume (e.g. 'discard=on,size=80G')
                                # borrows the existing disk's volume; size is owned by the
                                # resize above. Only config.put if non-size attrs differ.
                                put_val = _disk_put_value(str(val), cur_disk)
                                if _disk_base(put_val) != _disk_base(cur_disk):
                                    config_delta[fld] = put_val
                            else:
                                config_delta[fld] = val
                        # Snapshot the live config before any mutation. Fail closed:
                        # if the backup can't be written, skip this VM rather than
                        # change it with no record to fall back on.
                        if config_delta or delete_fields or detach_disks or resize_ops:
                            try:
                                bpath = backup_vm_config(root, pve_node, vmid, vm_name, cur_cfg)
                                print(f"         backed up config → {os.path.relpath(bpath, root)}")
                            except Exception as e:
                                print(f"         ERROR writing config backup, skipping {vm_name}: {e}",
                                      file=sys.stderr)
                                continue
                        try:
                            # Preserve PVE-assigned UUID when updating smbios1.
                            if "smbios1" in config_delta:
                                uuid = _smbios_uuid(str(cur_cfg.get("smbios1", "")))
                                if uuid:
                                    config_delta["smbios1"] = _inject_smbios_uuid(
                                        str(config_delta["smbios1"]), uuid
                                    )
                            # Preserve the PVE-assigned MAC when updating a NIC.
                            # Desired net strings omit the MAC; without this any
                            # netN write (queues, bridge, …) makes PVE assign a
                            # fresh one. _norm strips MACs for comparison, so
                            # re-injecting here causes no perpetual drift.
                            for net_fld in [f for f in config_delta if _NET_RE.match(f)]:
                                mac = _net_mac(str(cur_cfg.get(net_fld, "")))
                                if mac:
                                    config_delta[net_fld] = _inject_net_mac(
                                        str(config_delta[net_fld]), mac
                                    )
                            all_deletes = sorted(delete_fields + detach_disks)
                            if config_delta or all_deletes:
                                put_args = _preprocess_api(config_delta)
                                if all_deletes:
                                    put_args["delete"] = ",".join(all_deletes)
                                prox.nodes(pve_node).qemu(vmid).config.put(**put_args)
                            for disk_fld, new_sz in sorted(resize_ops.items()):
                                prox.nodes(pve_node).qemu(vmid).resize.put(
                                    disk=disk_fld, size=new_sz
                                )
                        except Exception as e:
                            print(f"         ERROR applying config: {e}", file=sys.stderr)
                            continue

                        # ── Pending-change reboot ──────────────────────────────
                        if is_running:
                            pending = get_pending_changes(prox, pve_node, vmid)
                            if pending or approved_queue_nets:
                                reasons: List[str] = []
                                if pending:
                                    reasons.append(f"{len(pending)} field(s) pending stop+start — {sorted(pending)}")
                                if approved_queue_nets:
                                    reasons.append(f"queues changed on {', '.join(approved_queue_nets)}")
                                print(f"  PEND   {vm_name}: {'; '.join(reasons)}")
                                # A queues reboot was already consented to above, so
                                # don't prompt again; only ask for other pending fields.
                                do_reboot = bool(approved_queue_nets) or args.reboot_on_pending or (
                                    args.yes or _confirm(
                                        f"  Reboot {vm_name!r} to apply changes?"
                                    )
                                )
                                if do_reboot:
                                    print(f"  Shutting down {vm_name} (graceful)…")
                                    try:
                                        shutdown_start_vm(prox, pve_node, vmid)
                                        print(f"  Started.")
                                        total_changes += 1
                                    except Exception as e:
                                        print(f"  ERROR during shutdown+start: {e}", file=sys.stderr)

                # ── Unused disk warnings ───────────────────────────────────────
                # Re-read config after potential detach so unusedN is up to date.
                try:
                    fresh_cfg = prox.nodes(pve_node).qemu(vmid).config.get() if not args.dry_run else cur_cfg
                except Exception:
                    fresh_cfg = cur_cfg
                unused = _get_unused_disks(fresh_cfg)
                if unused:
                    for uk, uv in sorted(unused.items()):
                        print(f"  WARN   {vm_name}: detached disk {uk}={uv!r}"
                              f" — use sync --prune-unused-disks to delete permanently")
                    if getattr(args, "prune_unused_disks", False) and not args.dry_run:
                        to_del = sorted(unused.keys())
                        print(f"  Unused disk(s) to DELETE permanently: "
                              f"{', '.join(f'{k}={unused[k]!r}' for k in to_del)}")
                        if not args.yes and not _confirm(
                            f"  Permanently delete {len(to_del)} unused disk(s) on {vm_name}?"
                        ):
                            print("  Skipped.")
                        else:
                            # Snapshot first. NB: this records the unusedN volume
                            # reference only, not the disk data being deleted —
                            # it is not a restore point for the disk contents.
                            try:
                                bpath = backup_vm_config(root, pve_node, vmid, vm_name, fresh_cfg)
                                print(f"  Backed up config → {os.path.relpath(bpath, root)}")
                            except Exception as e:
                                print(f"         ERROR writing config backup, skipping disk prune: {e}",
                                      file=sys.stderr)
                                continue
                            try:
                                prox.nodes(pve_node).qemu(vmid).config.put(
                                    delete=",".join(to_del)
                                )
                                print(f"  Deleted: {', '.join(to_del)}")
                                total_changes += 1
                            except Exception as e:
                                print(f"         ERROR deleting unused disks: {e}", file=sys.stderr)

        # ── Prune ──────────────────────────────────────────────────────────────

        if args.prune:
            to_prune = [
                (vmid, vm_info)
                for vmid, vm_info in sorted(existing.items())
                if vmid not in desired_ids
                and has_managed_tag(str(vm_info.get("tags") or ""), managed_tag)
            ]
            skipped = [
                vm_info for vmid, vm_info in sorted(existing.items())
                if vmid not in desired_ids
                and not has_managed_tag(str(vm_info.get("tags") or ""), managed_tag)
            ]
            for vm_info in skipped:
                label = f"{vm_info.get('name', '?')} (vmid {vm_info['vmid']})"
                print(f"  SKIP   {label}: missing tag '{managed_tag}' — not owned by this tool")

            if to_prune and not args.dry_run:
                print(f"\n  The following {len(to_prune)} VM(s) will be DELETED:")
                for vmid, vm_info in to_prune:
                    print(f"    vmid {vmid}  '{vm_info.get('name', '?')}'  [{vm_info.get('status', '?')}]")
                if not args.yes and not _confirm(f"\n  Confirm deletion of {len(to_prune)} VM(s)?"):
                    print("  Prune aborted.")
                    to_prune = []

            for del_vmid, del_info in to_prune:
                label = f"{del_info.get('name', '?')} (vmid {del_vmid})"
                print(f"  -PRUNE {label}")
                total_changes += 1
                if not args.dry_run:
                    # Snapshot before pruning. Fail closed — skip VMs we can't back up.
                    try:
                        del_cfg = prox.nodes(pve_node).qemu(del_vmid).config.get()
                        bpath = backup_vm_config(
                            root, pve_node, del_vmid, str(del_info.get("name") or del_vmid), del_cfg
                        )
                        print(f"         backed up config → {os.path.relpath(bpath, root)}")
                    except Exception as e:
                        print(f"         ERROR writing config backup, skipping prune of {label}: {e}",
                              file=sys.stderr)
                        continue
                    try:
                        if del_info.get("status", "stopped") != "stopped":
                            upid = prox.nodes(pve_node).qemu(del_vmid).status.stop.post()
                            wait_task(prox, pve_node, upid)
                        upid = prox.nodes(pve_node).qemu(del_vmid).delete()
                        if upid:
                            wait_task(prox, pve_node, upid)
                    except Exception as e:
                        print(f"         ERROR: {e}", file=sys.stderr)

    suffix = " (dry run)" if args.dry_run else ""
    print(f"\nDone — {total_changes} change(s) applied{suffix}.")


# ── Main ───────────────────────────────────────────────────────────────────────

def _add_common_args(p: argparse.ArgumentParser) -> None:
    p.add_argument("--flake-root", metavar="DIR", help="Path to flake root (default: git root)")
    p.add_argument("--verify-ssl", action="store_true", default=False, help="Verify TLS certificates")
    p.add_argument(
        "--managed-tag",
        default=DEFAULT_MANAGED_TAG,
        metavar="TAG",
        help=f"Tag stamped on owned VMs (default: {DEFAULT_MANAGED_TAG})",
    )


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Manage Proxmox VMs declared in proxmox.nix files."
    )
    # Common args on the top-level parser so they work before the subcommand name
    # (the shell wrapper passes --flake-root before "$@").
    _add_common_args(ap)
    sub = ap.add_subparsers(dest="command", required=True)

    # ── sync subcommand ────────────────────────────────────────────────────────
    sp = sub.add_parser("sync", help="Sync VMs to desired state (default operation)")
    sp.add_argument("--dry-run", action="store_true", help="Show planned changes without applying them")
    sp.add_argument("--prune", action="store_true", help="Delete VMs absent from desired state")
    sp.add_argument("--yes", "-y", action="store_true", help="Skip confirmation prompt for --prune")
    sp.add_argument("--node", metavar="NAME", help="Limit to this inventory node name")
    sp.add_argument(
        "--ignore",
        action="append",
        default=[],
        metavar="RULE",
        help="Inline ignore rule (vm_name|field glob, prefix ! to re-include)",
    )
    sp.add_argument(
        "--ignore-file",
        type=pathlib.Path,
        metavar="FILE",
        help="Ignore file (default: .proxmoxignore and proxmox/.proxmoxignore)",
    )
    sp.add_argument(
        "--no-colmena",
        action="store_true",
        default=False,
        help="Skip colmena apply + reboot after creating a new VM",
    )
    sp.add_argument(
        "--prune-unused-disks",
        action="store_true",
        default=False,
        help="Permanently delete unusedN volumes on managed VMs (asks for confirmation; combine with -y to skip)",
    )
    sp.add_argument(
        "--reboot-on-pending",
        action="store_true",
        default=False,
        help="Automatically stop+start VMs that have pending config changes requiring a reboot (no prompt)",
    )

    # ── status subcommand ──────────────────────────────────────────────────────
    stp = sub.add_parser("status", help="Show sync state of all managed VMs")
    stp.add_argument("--node", metavar="NAME", help="Limit to this inventory node name")

    # ── destroy subcommand ─────────────────────────────────────────────────────
    dp = sub.add_parser("destroy", help="Delete a single managed VM by host key")
    dp.add_argument(
        "host",
        metavar="DOTTED_PATH",
        help="Host key to destroy, e.g. server.home.myhost",
    )
    dp.add_argument("--force", "-f", action="store_true", help="Skip confirmation prompt")

    # ── import subcommand ──────────────────────────────────────────────────────
    ip = sub.add_parser(
        "import",
        help="Read a live VM's config from PVE and write proxmox.nix",
    )
    ip.add_argument("--vmid", required=True, type=int, metavar="ID", help="VM ID to import")
    ip.add_argument(
        "--host",
        required=True,
        metavar="DOTTED_PATH",
        help="Destination host key, e.g. server.home.myhost (maps to hosts/server/home/myhost/)",
    )
    ip.add_argument(
        "--node",
        required=True,
        metavar="NAME",
        help="Inventory node name from proxmox/nodes.nix to read the VM from",
    )
    ip.add_argument("--force", action="store_true", help="Overwrite proxmox.nix if it already exists")

    # ── import-interactive subcommand ──────────────────────────────────────────
    ii = sub.add_parser(
        "import-interactive",
        help="Interactively map unmanaged VMs on a node to host keys and import them",
    )
    ii.add_argument(
        "--node",
        default=None,
        metavar="NAME",
        help="Inventory node name (prompted if omitted and multiple nodes exist)",
    )
    ii.add_argument("--force", action="store_true", help="Overwrite proxmox.nix if it already exists")

    # ── setup-token subcommand ─────────────────────────────────────────────────
    tp = sub.add_parser(
        "setup-token",
        help="Create a least-privilege role + API token for proxmox-sync on a node",
    )
    tp.add_argument(
        "--node",
        required=True,
        metavar="NAME",
        help="Inventory node name from proxmox/nodes.nix to configure",
    )
    tp.add_argument(
        "--user",
        default="proxmox-sync@pve",
        metavar="USER@REALM",
        help="PVE user to create the token under (default: proxmox-sync@pve)",
    )
    tp.add_argument(
        "--token-name",
        default="proxmox-sync",
        metavar="NAME",
        help="Token name (default: proxmox-sync)",
    )
    tp.add_argument(
        "--role-name",
        default="proxmox-sync",
        metavar="NAME",
        help="Role name to create/update (default: proxmox-sync)",
    )
    tp.add_argument(
        "--create-user",
        action="store_true",
        help="Create the PVE user if it does not exist (pve realm only)",
    )
    tp.add_argument(
        "--force",
        action="store_true",
        help="Delete and recreate the token if it already exists",
    )
    tp.add_argument(
        "--rotate",
        action="store_true",
        help="Rotate an existing token: delete + recreate it and rewrite the env file (skips role/user/ACL setup)",
    )

    args = ap.parse_args()

    # Resolve flake root (shared by all subcommands)
    if args.flake_root:
        root = args.flake_root
    else:
        try:
            root = subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"], text=True
            ).strip()
        except subprocess.CalledProcessError:
            root = os.getcwd()
    repo = pathlib.Path(root)

    if args.command == "sync":
        cmd_sync(args, root, repo)
    elif args.command == "status":
        cmd_status(args, root, repo)
    elif args.command == "destroy":
        cmd_destroy(args, root, repo)
    elif args.command == "import":
        cmd_import(args, root, repo)
    elif args.command == "import-interactive":
        cmd_import_interactive(args, root, repo)
    elif args.command == "setup-token":
        cmd_setup_token(args, root, repo)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        # Exit cleanly on Ctrl-C instead of dumping a traceback. 130 is the
        # conventional shell exit code for a process killed by SIGINT.
        print("\nInterrupted.", file=sys.stderr)
        sys.exit(130)
