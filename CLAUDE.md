## Overview

This is a personal NixOS infrastructure flake managing routers, servers, and desktops across home labs, hosting providers (Hetzner, Cogent, netcup), and the DN42 network. It uses **flake-parts** for modular flake composition, **Colmena** for fleet deployment, **agenix** for secrets, **disko** for declarative disks, and a custom DNS-zone and Proxmox-VM generation pipeline.

The repo deeply depends on the `nixos` MCP server for package/option lookups — prefer it over `nix search`.

## NixOS MCP usage

Use the `pi-nixos-mcp` wrapper for Nix/NixOS package, option, Home Manager, nix-darwin, flake, Nixvim, wiki, nix.dev, Noogle, and NixHub lookups. Prefer this over `nix search` or guessing option/package names.

```bash
# List available MCP tools
pi-nixos-mcp --tools

# General Nix/NixOS/Home Manager/etc. query; the default tool is `nix`
pi-nixos-mcp '{"action":"search","query":"nginx"}'
pi-nixos-mcp nix '{"action":"info","query":"services.nginx.enable","type":"option"}'

# Package version history from NixHub
pi-nixos-mcp nix_versions '{"query":"firefox","version":"150"}'
```

Available tools currently:

- `nix` — query NixOS, Home Manager, Darwin, FlakeHub, flakes, Nixvim, Wiki, nix.dev, Noogle, NixHub.
- `nix_versions` — get package version history from NixHub.io.

If the wrapper cannot find `mcp-nixos`, ensure the dev shell is active/restarted; it is included in `parts/nix-develop.nix`.

## Common commands

A dev shell is provided via flake `devShells.default` and auto-loaded by `direnv` (`.envrc`). It exposes the `lhflake` wrapper plus ansible, terraform, packer, nixd, etc. `GIT_ROOT` is exported by direnv and is **required** by host `secrets.nix` files (they read `$GIT_ROOT/secrets/age_pubkeys.nix`).

```bash
# Format / lint everything (treefmt: nixfmt, statix, deadnix, shellcheck, shfmt, prettier)
nix fmt

# Build a single host's system closure
nix build .#colmenaHive.nodes.<host-key>.config.system.build.toplevel
#   e.g. <host-key> = router.example.core  (dot-separated path under hosts/)

# Deploy with Colmena (host keys match the dotted inventory names)
colmena apply --on <host-key>
colmena apply --on <host-key> --reboot      # Apply on Reboot, usefull when upgrading a NixOS major version

# Custom multi-tool wrapper (auto-detects flake root via git)
lhflake technitium-zone-sync # push DNS zones to Technitium
lhflake proxmox-sync         # reconcile Proxmox VMs with proxmox.nix declarations
lhflake wg-rekey             # regenerate a WireGuard keypair/PSK between two hosts

# The lhflake subcommands are also flake apps:
nix run .#proxmox-sync -- <subcommand> [flags]
```

## Architecture

### Flake composition (`flake.nix`)

`flake-parts.lib.mkFlake` imports a `flake-part.nix` from each subsystem (`dns/`, `disko/`, `modules/`, `home-manager/`, `profiles/`, `packer/`, `proxmox/`, `tools/*`, `nftables/`, `parts/`). `nixpkgs`/`home-manager` track the current stable; `nixos-unstable` is available as `pkgsUnstable` for cherry-picking newer packages. Systems: `x86_64-linux`, `aarch64-linux`.

### Hosts and the inventory pipeline — the central pattern

Every machine lives under `hosts/<path>/` and is identified by a **dot-separated key** derived from its path (e.g. `hosts/router/example/core/` → `router.example.core`). Each host directory contains a `meta.nix` with `deployment` info (targetHost, sshUser, sshPort, tags) and optional `dependencies`, plus a `configuration.nix` entrypoint. `meta.nix` may be a plain attrset or a function `{ lib, ... }: lib.mkServer { ... }` receiving the helper lib (`tools/inventory/helpers.nix`); deployment defaults (sshUser=root, sshPort=22) are merged automatically, so a host only declares what differs. `dependencies` is a list of host keys or tags (consumed later for ordered apply+reboot).

`parts/inventory.nix` builds the `colmenaHive` and `nixosConfigurations` **live at evaluation time** — it walks `hosts/**/meta.nix` via `tools/inventory/collect-meta.nix` (a builtins-only recursive walk) and maps each host into a node/system. There is **no codegen step**: adding/moving a host or editing `meta.nix` takes effect on the next flake evaluation, nothing to regenerate. The DNS (`dns/dns-inventory.nix` → `flake.dnsConfigurations`) and Proxmox (`proxmox/proxmox-inventory.nix` → `flake.proxmoxVMs`) inventories are built the same way — live walks of `dns/zones/**/zone.nix` and `hosts/**/proxmox.nix`, no regeneration.

A host's `configuration.nix` imports composable pieces: profile modules (`inputs.self.nixosModules.profile_*`), a disko config, and sibling files (`network.nix`, `firewall.nix`, `agenix.nix`, `proxmox.nix`, `network/wireguard/*.nix`) Split into files when usefull. Hosts set their role via `lh.roleSystem.systemType = "router" | "server" | "desktop"`.

### Modules (`modules/`) — the `lh.*` namespace

`modules/default.nix` aggregates all custom NixOS modules, exported as `nixosModule.default`. Custom options live under the **`lh.*`** namespace (`lh.firewall`, `lh.roleSystem`, `lh.cosmetic`, `lh.security`, etc.). Subtrees: `networking/`, `router/`, `services/`, `system/`, `security/`, `role-system/` (desktop/server/router role bundles), `cosmetic/`, `packages/` (custom derivations like `selfhst-icons`), `printing/`, `helper/`, `user-mgmt/`.

### Profiles (`profiles/`)

Reusable host bundles exported as `nixosModules.profile_*`: `defaults` (applied to every host via inventory — sets default stateVersion, agenix identity path, locale, nix config, home-manager, overlays), `qemu-guest-x86_64-linux`.

### Routing (firewall)

Router hosts set `lh.roleSystem.systemType = "router"` and use the routing modules under `modules/router/` (`rtr.nix`, `radvd.nix`, `dhcp-relay.nix`). Firewalls use the **notnft-based `lh.firewall` framework** (`modules/networking/firewall.nix` + `nftables/`); see `docs/nft-framework.md` for chain topology and options, and `docs/notnft.md` for the DSL.

### Secrets (agenix)

Root `secrets/secrets.nix` and per-host `secrets.nix` define agenix recipient rules; `*.age` files are committed, plaintext under `secrets/` is gitignored (see `.gitignore` for the allow-list). Per-host `agenix.nix` declares `age.secrets.*` (file, owner, mode). The agenix identity is the host SSH key (`age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ]`). Per-host `secrets.nix` files require `$GIT_ROOT` to be set (direnv provides it).

Never Decrypt any Secrets but you may set a secret to a value by piping it to `agenix -e`; agenix accepts stdin and should be preferred over calling `age` directly so recipient rules from `secrets.nix` are honored, e.g. `printf '%s\n' "$value" | GIT_ROOT=/path/to/repo agenix -e ./secrets/example.age`.

### DNS (`dns/`)

Zones in `dns/zones/<domain>/zone.nix` are built with `nix-community/dns.nix` into the `dns-zones` package (also has a `dn42/` defaults set). `dns/helpers/` provides record/merge/network helpers. `dns/dns-inventory.nix` walks the zone dirs live, so a new zone directory is picked up automatically. Sync to the Technitium server with `lhflake technitium-zone-sync`.

### Proxmox (`proxmox/`, tools/proxmox)

Per-host `proxmox.nix` files declare desired VM specs; `proxmox/nodes.nix` lists PVE nodes. `lhflake proxmox-sync` reconciles them via the PVE API and can trigger a post-create `colmena apply boot`. See `docs/proxmox-sync.md`.

### Home-manager (`home-manager/`)

User configs under `home-manager/users/leon/` (cli/desktop splits, browser, vscode, git, ssh, persistence/impermanence). Wired into hosts via the defaults profile.

## Conventions

- `parts/inventory.nix`, `dns/dns-inventory.nix`, and `proxmox/proxmox-inventory.nix` are all live code now (edit them directly if you change the wiring; per-host/zone data lives in `meta.nix` / `zone.nix` / `proxmox.nix`). No inventory regeneration step exists.
- **No monolithic files.** Split concerns into separate files — one file per logical unit (e.g. `lib/pkgs.nix` for pkgs instantiation, `lib/flake-part.nix` as the wiring entry point). `flake-part.nix` files are entry points only; logic lives in dedicated sibling files.
- New custom options belong under the `lh.*` namespace.
- Editing `meta.nix` or the `hosts/` layout needs no regeneration — `parts/inventory.nix` picks it up live on the next evaluation.
- Adding a zone directory under `dns/zones/` or a `proxmox.nix` under `hosts/` needs no regeneration — the live inventories pick it up on the next evaluation.
- Never manually update SOA serials in zone files — Technitium sync manages them automatically.
- Run `nix fmt` before committing; `hardware-configuration.nix` is exempt from formatting.
