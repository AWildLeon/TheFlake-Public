#
# Proxmox inventory: maps each host's dotted key -> path of its proxmox.nix,
# built live by walking hosts/**/proxmox.nix at evaluation time (no codegen).
#
{ self }:
let
  walk =
    dir: segs:
    let
      entries = builtins.readDir dir;
      subdirs = builtins.filter (n: entries.${n} == "directory") (builtins.attrNames entries);

      this =
        if entries ? "proxmox.nix" then
          [
            {
              name = builtins.concatStringsSep "." segs;
              value = dir + "/proxmox.nix";
            }
          ]
        else
          [ ];

      children = builtins.concatMap (n: walk (dir + "/${n}") (segs ++ [ n ])) subdirs;
    in
    this ++ children;
in
builtins.listToAttrs (walk (self + /hosts) [ ])
