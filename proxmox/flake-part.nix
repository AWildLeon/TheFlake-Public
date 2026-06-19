{ self, ... }:
{
  flake =
    let
      # Live map of host dotted-key -> proxmox.nix path (walks hosts/** at eval
      # time; adding/moving a proxmox.nix is picked up automatically).
      vmPaths = import (self + /proxmox/proxmox-inventory.nix) { inherit self; };
      # `self` lets the from-host helpers read a machine's NixOS network config.
      proxmoxLib = import (self + /proxmox/lib.nix) { inherit self; };

      # If a proxmox.nix is a function it receives { lib } so it can use the helpers.
      # The lib is bound to this host so `lib.mkIpConfigFromHost { }` defaults its
      # `machine` to the host the file lives under (the dotted vmPaths key, which is
      # also the nixosConfigurations key).
      # Plain attrset files (no argument) are imported as-is — fully backward-compatible.
      evalVM =
        name: path:
        let
          expr = import path;
        in
        if builtins.isFunction expr then expr { lib = proxmoxLib.withHost name; } else expr;
    in
    {
      proxmoxNodes = import (self + /proxmox/nodes.nix);
      proxmoxVMs = builtins.mapAttrs evalVM vmPaths;
      inherit proxmoxLib;
    };
}
