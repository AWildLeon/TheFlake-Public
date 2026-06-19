# Offline collector used by tools/inventory/generate.py.
#
# Walks the hosts tree, imports every `meta.nix` (which may be a plain attrset
# or a function `{ lib, ... }: ...` receiving the helper lib), merges deployment
# defaults, expands `#dependency_group` references, and returns a list of
# `{ name; meta; rel_path; }` records.
#
# Invoked as:  nix eval --impure --json --expr \
#   'import /abs/tools/inventory/collect-meta.nix { root = /abs/hosts; }'
{ root }:
let
  lib = import ./helpers.nix;
  dependencyGroupDefs = import ./dependency-groups.nix;

  hostsDirName = baseNameOf (toString root);

  isGroupRef = dep: builtins.isString dep && builtins.substring 0 1 dep == "#";
  groupRefName = dep: builtins.substring 1 ((builtins.stringLength dep) - 1) dep;

  # Collect every directory under `dir` (whose path segments relative to the
  # hosts root are `segs`) that contains a meta.nix.
  walk =
    dir: segs:
    let
      entries = builtins.readDir dir;
      subdirs = builtins.filter (n: entries.${n} == "directory") (builtins.attrNames entries);

      self =
        if entries ? "meta.nix" then
          let
            raw = import (dir + "/meta.nix");
            v = if builtins.isFunction raw then raw { inherit lib; } else raw;
          in
          [
            {
              name = builtins.concatStringsSep "." segs;
              rel_path = builtins.concatStringsSep "/" ([ hostsDirName ] ++ segs);
              meta = {
                deployment = lib.defaults // (v.deployment or { });
                system = v.system or "x86_64-linux";
                dependencies = v.dependencies or [ ];
                dependencyGroups = v.dependencyGroups or [ ];
                dependencyGroupMemberships = v.dependencyGroupMemberships or [ ];
                sshPublicKeys = v.sshPublicKeys or (if v ? sshPublicKey then [ v.sshPublicKey ] else [ ]);
              };
            }
          ]
        else
          [ ];

      children = builtins.concatMap (n: walk (dir + "/${n}") (segs ++ [ n ])) subdirs;
    in
    self ++ children;

  rawHosts = walk root [ ];

  groupMembers =
    groupName:
    map (h: h.name) (
      builtins.filter (h: builtins.elem groupName h.meta.dependencyGroupMemberships) rawHosts
    );

  expandGroupRef =
    dep:
    let
      name = groupRefName dep;
      def = dependencyGroupDefs.${name} or { mode = "all_needed"; };
    in
    {
      inherit name;
      mode = def.mode or "all_needed";
      members = groupMembers name;
    };

  resolveHost =
    h:
    let
      deps = h.meta.dependencies or [ ];
      strictDeps = builtins.filter (dep: !(isGroupRef dep)) deps;
      groupRefs = builtins.filter isGroupRef deps;
    in
    h
    // {
      meta = h.meta // {
        dependencies = strictDeps;
        dependencyGroups = h.meta.dependencyGroups ++ map expandGroupRef groupRefs;
      };
    };
in
map resolveHost rawHosts
