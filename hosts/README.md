# hosts/

Each machine lives in its own directory under `hosts/<path>/` and is identified
by a **dot-separated key** derived from its path
(e.g. `hosts/router/example/core/` → `router.example.core`).

The inventory walks `hosts/**/meta.nix` live at evaluation time
(`tools/inventory/collect-meta.nix`) — there is no codegen step. Adding or moving
a host directory takes effect on the next flake evaluation.

A host directory typically contains:

- `meta.nix` — `deployment` info (targetHost, sshUser, sshPort, tags), optional
  `dependencies`. May be a plain attrset or a function `{ lib, ... }: lib.mkServer { ... }`.
- `configuration.nix` — entrypoint importing profile modules
  (`inputs.self.nixosModules.profile_*`), a disko config, and sibling files.
- optional siblings: `network.nix`, `firewall.nix`, `agenix.nix`, `proxmox.nix`,
  `secrets.nix`, `network/wireguard/*.nix`, `hardware-configuration.nix`.

See `templates/` for ready-to-copy machine skeletons.

This template ships with no concrete hosts — drop your own here.
