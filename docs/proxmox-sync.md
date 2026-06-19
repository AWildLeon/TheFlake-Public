# proxmox-sync

`proxmox-sync` keeps Proxmox VMs in the state declared in Nix files inside
the repository. It reads desired VM specs from per-host `proxmox.nix` files
and a node inventory from `proxmox/nodes.nix`, then creates, updates, or
deletes VMs through the Proxmox VE API.

## Running

```bash
nix run .#proxmox-sync -- <subcommand> [flags]
```

All subcommands auto-detect the flake root via `git rev-parse --show-toplevel`.

---

## First-time setup

### 1. Add a node to `proxmox/nodes.nix`

```nix
{
  <name> = {
    url     = "https://10.0.0.1:8006";
    envFile = "~/.secrets/proxmox-<name>.env";
    # nodeName = "pve";  # only needed when the cluster has multiple nodes
  };
}
```

### 2. Create a least-privilege token

Run once with admin credentials in the env file:

```bash
nix run .#proxmox-sync -- setup-token --node <name> --create-user
```

This creates the `proxmox-sync` role, `proxmox-sync@pve` user, and
`proxmox-sync@pve!proxmox-sync` API token, then prints what to write to the
env file. Replace the admin credentials with the printed token secret.

Env file format:

```
PROXMOX_TOKEN_ID=proxmox-sync@pve!proxmox-sync
PROXMOX_TOKEN_SECRET=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Password auth is also supported (`PROXMOX_USER` + `PROXMOX_PASSWORD`).

### 3. Declare a VM

Create `hosts/<path>/proxmox.nix`. The path segments become the dotted host
key used throughout the tool (e.g. `hosts/server/home/myhost/proxmox.nix` →
key `server.home.myhost`).

There are two equivalent styles — choose whichever fits your preference.

---

## Writing proxmox.nix

### Style 1 — classic (plain attrset, relative imports)

Simple and self-contained. Use when the file is standalone or you prefer
explicit relative paths.

```nix
let small = import ../../../../proxmox/profiles/small-vm.nix;
in small // {
  vmid     = null;      # null = auto-assign; the tool writes the value back
  node     = "<name>";
  template = 10002;     # vmid of the template to clone from

  name = "my-vm";

  cores  = 2;
  memory = 2048;
  boot   = "order=virtio0";

  net0      = "virtio,bridge=vmbr0";
  ipconfig0 = "ip=10.0.0.10/24,gw=10.0.0.1";
  ciuser    = "root";
  sshkeys   = "ssh-ed25519 AAAA…";
}
```

With DHCP and multiple SSH keys:

```nix
let medium = import ../../../../proxmox/profiles/medium-vm.nix;
in medium // {
  vmid     = null;
  node     = "<name>";
  template = 10002;

  name = "my-vm";

  net0      = "virtio,bridge=vmbr0";
  ipconfig0 = "ip=dhcp";
  ciuser    = "root";
  sshkeys   = ''
    ssh-ed25519 AAAA…key1
    ssh-ed25519 AAAA…key2
  '';
}
```

---

### Style 2 — with helpers (recommended)

Declare `{ lib }:` at the top and the flake passes `proxmox/lib.nix`
automatically. No relative paths needed for profiles; format strings are
replaced by small helper functions.

```nix
{ lib }:
lib.profiles.small // {
  vmid     = null;
  node     = "<name>";
  template = 10002;

  name = "my-vm";

  cores  = 2;
  memory = 2048;
  boot   = lib.mkBoot "virtio0";

  net0      = lib.mkNet "vmbr0" {};
  ipconfig0 = lib.mkIpConfig { ip = "10.0.0.10/24"; gw = "10.0.0.1"; };
  ciuser    = "root";
  sshkeys   = lib.mkSshKeys [
    "ssh-ed25519 AAAA…key1"
    "ssh-ed25519 AAAA…key2"
  ];
}
```

#### Available helpers

**Profiles** — import by name, no relative path:

```nix
lib.profiles.small    # 2 cores, 2 GB
lib.profiles.medium   # 4 cores, 4 GB
lib.profiles.big      # 8 cores, 8 GB
```

All profiles set `machine = "q35"`, `bios = "ovmf"`, `cpu = "host"`,
`kvm = 1`, `agent = 1`, `scsihw = "virtio-scsi-single"`, `ostype = "l26"`,
`serial0 = "socket"`, `vga = "type=serial0"`,
`rng0 = "source=/dev/urandom,…"`, `onboot = 1`,
`smbios1 = "manufacturer=Leon Hubrich,product=PVE-Flake-VM"`.

---

**`lib.mkNet bridge opts`** — build a `netN` string:

```nix
lib.mkNet "vmbr0" {}
# → "virtio,bridge=vmbr0"

lib.mkNet "vmbr0" { firewall = true; }
# → "virtio,bridge=vmbr0,firewall=1"

lib.mkNet "vmbr0" { model = "e1000"; tag = 100; rate = 100; }
# → "e1000,bridge=vmbr0,tag=100,rate=100"

lib.mkNet "vmbr0" { mac = "bc:24:11:00:00:01"; }
# → "virtio=bc:24:11:00:00:01,bridge=vmbr0"
```

Available options: `model` (default `"virtio"`), `mac` (string),
`firewall` (bool), `tag` (int), `rate` (MB/s int), `queues` (int), `mtu` (int).

When `mac` is omitted the string carries no MAC: proxmox-sync strips the
PVE-assigned MAC before comparing `netN` and re-injects it on write, so an
update (queues, bridge, …) never makes PVE assign a fresh MAC. Pin `mac` to
fix the address across VM _re-creation_ — required where a guest renames
interfaces by MAC (`lh.networking.staticInterfaceNames`), since a recreated VM
would otherwise come up with random MACs and misnamed interfaces.

---

**`lib.mkIpConfig opts`** — build an `ipconfigN` string:

```nix
lib.mkIpConfig { ip = "10.0.0.5/24"; gw = "10.0.0.1"; }
# → "ip=10.0.0.5/24,gw=10.0.0.1"

lib.mkIpConfig {}
# → "ip=dhcp"  (default)

lib.mkIpConfig { ip = "dhcp"; ip6 = "dhcp6"; }
# → "ip=dhcp,ip6=dhcp6"

lib.mkIpConfig { ip = "10.0.0.5/24"; gw = "10.0.0.1"; ip6 = "2001:db8::5/64"; gw6 = "2001:db8::1"; }
# → "ip=10.0.0.5/24,gw=10.0.0.1,ip6=2001:db8::5/64,gw6=2001:db8::1"
```

---

**`lib.mkIpConfigFromHost opts`** — build an `ipconfigN` string by reading the
host's real NixOS network config instead of hardcoding it (the proxmox analogue
of the dns `…FromMachine` helpers). It pulls the address (with prefix) and
gateway from `systemd.network.networks` (and, as a fallback,
`networking.interfaces` + `networking.defaultGateway{,6}`), so the cloud-init
ipconfig can't silently drift from what the guest is actually configured for.

```nix
lib.mkIpConfigFromHost { }
# machine defaults to the host this proxmox.nix lives under (its dotted
# nixosConfigurations key, e.g. "server.home.dns")
# → "ip=10.10.10.10/24,gw=10.10.10.1,ip6=2a14:47c0:e002:1010::10/64,gw6=…::1"

lib.mkIpConfigFromHost { machine = "server.home.dns"; }   # pick another host
lib.mkIpConfigFromHost { interface = "ens18"; }           # restrict to one iface
lib.mkIpConfigFromHost { ipv6 = false; }                  # IPv4 only
```

`machine` is the dotted `nixosConfigurations` key (the same key proxmox-sync
uses). `interface` selects a single network by its systemd-networkd name or
`matchConfig.Name`; when omitted, every interface on the host is considered and
the first address of each family wins. `ipv4` / `ipv6` (both default `true`)
toggle each family off.

---

**`lib.mkBoot disk`** — build a `boot` string:

```nix
lib.mkBoot "virtio0"
# → "order=virtio0"

lib.mkBoot "virtio0;net0"   # fallback to PXE if disk fails
# → "order=virtio0;net0"
```

---

**`lib.mkSshKeys [ key … ]`** — join SSH public keys with newlines:

```nix
lib.mkSshKeys [
  "ssh-ed25519 AAAA…"
  "ssh-rsa AAAB…"
]
```

---

**`lib.mkDisk storage size`** — new disk string for inline disk allocation:

```nix
lib.mkDisk "local-lvm" "20G"
# → "local-lvm:20G"
```

---

### Field reference

Every field the Proxmox API accepts can appear in `proxmox.nix` — there is no
allowlist. Set a field to `null` to delete it from the VM config.

| Tool fields | Meaning                                            |
| ----------- | -------------------------------------------------- |
| `vmid`      | VM ID; `null` = auto-assign and write back         |
| `node`      | Inventory node name from `proxmox/nodes.nix`       |
| `template`  | vmid of the template to clone from on first create |

All other fields are forwarded to the PVE API verbatim. See `pvesh usage
/nodes/<node>/qemu/<vmid>/config` on your node for the full field list.

**`smbios1`** — write human-readable strings; the tool base64-encodes them
for PVE and preserves the PVE-assigned UUID automatically:

```nix
smbios1 = "manufacturer=Acme Corp,product=my-vm";
```

---

## Subcommands

### `status`

Show the sync state of all managed VMs without making changes.

```bash
nix run .#proxmox-sync -- status [--node <name>]
```

| Column | Meaning                                                                       |
| ------ | ----------------------------------------------------------------------------- |
| VMID   | Proxmox VM ID                                                                 |
| NAME   | Host key (`server.home.myhost`)                                               |
| STATE  | `running` / `stopped` as reported by PVE                                      |
| SYNC   | `✓ in sync` · `~ N field(s) differ` · `✗ not created` · `⏳ N pending reboot` |

Unmanaged VMs (no `proxmox.nix`) are listed below the table.

Below that, a **To be deployed** section summarises exactly what a `sync` run
would change on the node — VMs to `+ create` (declared but not yet on the node,
or with no vmid assigned) and VMs to `~ update` (with the list of drifted
fields). The footer counts these as `… to deploy`:

```
  ▸ To be deployed (run `proxmox-sync sync`):
    + create     109  server.home.lhmail
    ~ update     103  server.home.dns  (ipconfig0, memory)

  12 desired  (9 in sync, 1 drifted, 2 missing)  |  3 to deploy  |  4 unmanaged
```

**Performance.** Display names not set explicitly in `proxmox.nix` are derived
from each host's `networking.fqdn` / `hostName`. These are resolved for all hosts
in a **single** batched `nix eval` (rather than one per VM) and cached under
`$XDG_CACHE_HOME/proxmox-sync/` keyed on the `hosts/` + `flake.lock` content, so
repeat runs are fast and only a change under `hosts/` recomputes them. Per-VM
Proxmox config reads are issued concurrently.

---

### `sync`

Reconcile all nodes: create missing VMs, update drifted config, optionally
prune removed ones.

```bash
nix run .#proxmox-sync -- sync [--dry-run] [--prune] [-y] [--node <name>]
```

| Flag                   | Effect                                                                  |
| ---------------------- | ----------------------------------------------------------------------- |
| `--dry-run`            | Print planned changes; touch nothing                                    |
| `--prune`              | Delete managed VMs absent from desired state (prompts for confirmation) |
| `--yes` / `-y`         | Skip all confirmation prompts (for CI)                                  |
| `--node NAME`          | Limit to one inventory node                                             |
| `--no-colmena`         | Skip post-create colmena deploy                                         |
| `--reboot-on-pending`  | Automatically shutdown+start VMs with pending changes                   |
| `--prune-unused-disks` | Permanently delete detached unusedN volumes                             |
| `--ignore RULE`        | Inline ignore rule (see [Ignore rules](#ignore-rules))                  |
| `--ignore-file FILE`   | Custom ignore file                                                      |

**Create lifecycle** (VM in desired state but not yet on PVE):

0. **Prerequisite** (unless `--no-colmena`): if the host is a NixOS host
   (`configuration.nix` + `meta.json` present), its `meta.json` must have
   `deployment.targetHost` set — that's where the post-create `colmena apply`
   connects. If it's unset the tool errors and **skips creation** (does not
   clone), so you never end up with an undeployable VM.
1. Clone the `template` vmid as a full clone.
2. Apply all config fields (`config.put`), stamping the `proxmox-sync` tag.
   Disk specs without a volume (e.g. `discard=on,size=80G`) borrow the cloned
   disk's volume; grows are applied via the resize API.
3. Start the VM, then write back an auto-assigned `vmid` to `proxmox.nix`.
4. If both `hosts/<path>/configuration.nix` and `hosts/<path>/meta.json` exist:
   wait for SSH on the `ipconfig0` IP, then run
   `colmena apply boot --on <host-key>`. The `boot` goal makes the new
   generation the boot default without live-activating it (avoids activation
   failures when the delta from the template is large). The tool then triggers
   a **non-blocking** reboot via the PVE API to activate it — it does not wait
   for the node to come back up. Because a brand-new VM generates fresh SSH host
   keys (and would again if recreated), this deploy ignores the host key and
   does not record it in `known_hosts` — colmena is handed a throwaway ssh
   config via `SSH_CONFIG_FILE` (`StrictHostKeyChecking no`,
   `UserKnownHostsFile /dev/null`) covering both the closure copy and activation.

If any step after the clone fails, the tool offers to delete the half-created
VM (auto-deletes under `--yes`).

**`vmid = null`** — The tool calls `GET /cluster/nextid`, avoids any IDs
already reserved in this run, assigns the next free one, and writes the value
back into `proxmox.nix`.

**Name resolution** — If `name` is absent from `proxmox.nix`, the tool tries:
`networking.fqdn` (used if it contains a dot) → `networking.hostName` → last
path segment of the host key.

**Disk resize** — Size changes on disk fields (`virtio0`, `scsi0`, etc.) are
applied via `PUT /qemu/{vmid}/resize`, not `config.put`. Units are normalised
so `15G` and `15360M` are treated as equal. Disk shrinks are blocked with a
warning.

**Disk detach** — Setting a disk field to `null` detaches it (the volume
becomes `unusedN`, data is safe). Use `--prune-unused-disks` to permanently
delete detached volumes.

**Pending changes** — Some fields (`memory`, `cores`, `cpu`, `machine`, etc.)
cannot be hot-applied to a running VM. The tool detects them via
`GET /qemu/{vmid}/pending`, annotates them with `⚠ requires reboot` in dry-run
output, and offers a graceful shutdown+start after applying.

---

### `destroy`

Delete a single managed VM by host key.

```bash
nix run .#proxmox-sync -- destroy server.home.myhost [--force]
```

Checks for the managed tag before deleting. Prompts for confirmation unless
`--force` / `-f` is passed. Attempts a graceful ACPI shutdown first; falls
back to force stop if the guest does not respond within 120 seconds.

---

### `import`

Snapshot a live VM's current config from PVE and write a `proxmox.nix`.

```bash
nix run .#proxmox-sync -- import \
  --vmid 100 \
  --host server.home.myhost \
  --node <name> \
  [--force]
```

The generated file is a flat attrset (Style 1). After importing:

- Remove fields you don't want the tool to manage (or add them to
  `.proxmoxignore`).
- Optionally convert to Style 2 and layer in a profile.
- Add `template = <vmid>;` to make the VM recreatable from a template.

`--force` overwrites an existing `proxmox.nix`.

---

### `setup-token`

Create a least-privilege PVE role and API token for the tool.

```bash
nix run .#proxmox-sync -- setup-token \
  --node <name> \
  [--create-user] \
  [--user proxmox-sync@pve] \
  [--token-name proxmox-sync] \
  [--role-name proxmox-sync] \
  [--force]
```

The role is idempotent — re-running `setup-token` updates the privilege set
if it changes in a future version. `--force` deletes and recreates the token
(the only way to recover a lost secret).

The role includes `SDN.Use`, required to attach a NIC to an SDN VNet/zone
(e.g. `net0 = lib.mkNet "DMZ" { … }` where `DMZ` is an SDN VNet). If you
created the token before this privilege was added and hit
`403 … (/sdn/zones/…, SDN.Use)` on create, just re-run `setup-token` to update
the role.

---

## Ignore rules

Declare fields to skip during sync in `.proxmoxignore` (repo root) or
`proxmox/.proxmoxignore`:

```
# Format: vm_name_glob|field_glob   (fnmatch, last match wins)
#         prefix ! to negate

*|description       # never overwrite description (managed in PVE UI)
*|balloon           # ignore balloon memory on all VMs
my-host|tags        # ignore tags on a specific VM
!prod-*|tags        # re-include tags for prod VMs
```

- Patterns are matched against `<host-key>|<field>` using `fnmatch`.
- Last matching rule wins.
- Prefix `!` to negate (re-include a previously ignored field).
- Inline rules: `--ignore 'pattern'` on any `sync` invocation.

---

## Managed tag

Every VM the tool creates or updates is stamped with the `proxmox-sync` tag.
Only tagged VMs are eligible for `--prune` or `destroy` deletion, so manually
created VMs are never touched.

Override the tag with `--managed-tag <tag>` on any subcommand.

---

## SSL

TLS verification is off by default (typical for self-signed Proxmox certs).
Pass `--verify-ssl` to enable it.
