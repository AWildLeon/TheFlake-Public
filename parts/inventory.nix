# Inventory: builds the Colmena hive and nixosConfigurations live by walking
# hosts/**/meta.nix at evaluation time (no codegen step). See
# tools/inventory/collect-meta.nix for the offline-safe walk and
# tools/inventory/helpers.nix for the `lib` helper passed to each meta.nix.
#
# Performance notes:
# - This file is on the hot path for every `colmena apply` and many `nix eval`s.
# - Avoid per-host nixpkgs imports. Import nixpkgs once per system and share the
#   resulting package sets between all hosts of that system.
# - Do not force `colmenaHive.nodes` unless a full NixOS eval is really needed.
#   Colmena's stock `deploymentConfig` is derived from evaluated nodes, which
#   means “read SSH targets/tags” turns into “evaluate every host”. We provide a
#   metadata-only fast path below because our deployment fields come exclusively
#   from hosts/**/meta.nix plus fixed Colmena defaults.
{ inputs, self, ... }:
let
  # `collect-meta.nix` returns records of the shape:
  #   { name = "router.home.core"; rel_path = "hosts/router/home/core"; meta = ...; }
  # It only imports meta.nix files, not host configuration.nix files, so this is
  # intentionally cheap and safe to use for metadata-only outputs.
  hosts = import (self + /tools/inventory/collect-meta.nix) {
    root = self + /hosts;
  };

  hostDir = h: self + ("/" + h.rel_path);

  hostSystem = h: h.meta.system or "x86_64-linux";

  # Colmena needs a global meta.nixpkgs. Most of this fleet is x86_64-linux, so
  # keep that as the default and only add node-specific nixpkgs for hosts that
  # actually use a different system.
  defaultSystem = "x86_64-linux";

  # Unique systems present in the inventory, plus the default system so the
  # global meta.nixpkgs always exists even if no host currently uses it.
  systems = builtins.attrNames ((builtins.groupBy hostSystem hosts) // { ${defaultSystem} = [ ]; });

  # Import nixpkgs once per system. A previous version imported nixpkgs once per
  # host via meta.nodeNixpkgs, causing Colmena to instantiate nixpkgs dozens of
  # times before reaching useful work.
  pkgsFor = builtins.listToAttrs (
    map (system: {
      name = system;
      value = import inputs.nixpkgs {
        inherit system;
        overlays = [ ];
      };
    }) systems
  );

  # Same idea for unstable. Keep it as a shared per-system package set and pass
  # it through specialArgs instead of importing nixos-unstable inside every host
  # module evaluation.
  pkgsUnstableFor = builtins.listToAttrs (
    map (system: {
      name = system;
      value = import inputs.nixos-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    }) systems
  );

  mkPkgs = system: pkgsFor.${system};

  mkPkgsUnstable = system: pkgsUnstableFor.${system};

  # Small builtins-only scanner used to decide whether optional top-level modules
  # are needed for a host. This avoids importing heavy modules such as Home
  # Manager or agenix for hosts that never use their options.
  #
  # Keep this conservative: false negatives break evaluation by omitting option
  # declarations. False positives only cost some eval time.
  hasSuffix =
    suffix: str:
    let
      strLen = builtins.stringLength str;
      suffixLen = builtins.stringLength suffix;
    in
    strLen >= suffixLen && builtins.substring (strLen - suffixLen) suffixLen str == suffix;

  dirContains =
    regex: dir:
    let
      entries = builtins.readDir dir;
      names = builtins.attrNames entries;
      matchesName =
        name:
        let
          type = entries.${name};
          path = dir + "/${name}";
        in
        if type == "directory" then
          dirContains regex path
        else if type == "regular" && hasSuffix ".nix" name then
          builtins.match regex (builtins.readFile path) != null
        else
          false;
    in
    builtins.any matchesName names;

  hostUses = h: {
    agenix = dirContains ".*(age[.]secrets|[.]/agenix[.]nix).*" (hostDir h);
    homeManager = dirContains ".*(lh[.]users|users[.]leon|home-manager).*" (hostDir h);
  };

  # Only non-default-system hosts need Colmena nodeNixpkgs entries. Default-system
  # hosts inherit meta.nixpkgs, which avoids forcing a giant nodeNixpkgs attrset.
  nonDefaultSystemHosts = builtins.filter (h: hostSystem h != defaultSystem) hosts;

  nodeNixpkgs = builtins.listToAttrs (
    map (h: {
      inherit (h) name;
      value = mkPkgs (hostSystem h);
    }) nonDefaultSystemHosts
  );

  # `nodeSpecialArgs` is evaluated by Colmena before module imports. This makes
  # `hostdirname` and `hostUses` available in `imports = ...` decisions without
  # falling into the usual `_module.args`/`config` import recursion trap.
  nodeSpecialArgs = builtins.listToAttrs (
    map (h: {
      inherit (h) name;
      value = {
        hostdirname = h.name;
        hostUses = hostUses h;
      }
      // (
        if hostSystem h == defaultSystem then { } else { pkgsUnstable = mkPkgsUnstable (hostSystem h); }
      );
    }) hosts
  );

  # Raw Colmena node definition. This is still the real source for full system
  # evaluation/builds (`colmenaHive.nodes`, `evalSelected`, `toplevel`, etc.).
  mkNode =
    h:
    { ... }:
    {
      deployment = {
        targetHost = h.meta.deployment.targetHost;
        targetUser = h.meta.deployment.sshUser;
        targetPort = h.meta.deployment.sshPort;
        tags = h.meta.deployment.tags;
        allowLocalDeployment = true;
      };

      imports = [
        (self + /profiles/hosts/defaults)
        (hostDir h + "/configuration.nix")
        {
          _module.args.hostdirname = h.name;
          _module.args.dependencies = h.meta.dependencies;
          _module.args.dependencyGroups = h.meta.dependencyGroups;
          _module.args.dependencyGroupMemberships = h.meta.dependencyGroupMemberships;
        }
      ];
    };

  # Standard nixosConfigurations output for `nix build`/manual inspection.
  # Unlike Colmena, nixosSystem receives specialArgs directly per host, so we can
  # pass the host-specific cached unstable package set here.
  mkSystem =
    h:
    inputs.nixpkgs.lib.nixosSystem {
      system = hostSystem h;
      specialArgs = {
        inherit inputs self;
        pkgsUnstable = mkPkgsUnstable (hostSystem h);
        hostdirname = h.name;
        hostUses = hostUses h;
        dependencies = h.meta.dependencies;
        dependencyGroups = h.meta.dependencyGroups;
        dependencyGroupMemberships = h.meta.dependencyGroupMemberships;
      };
      modules = [
        (self + /profiles/hosts/defaults)
        (hostDir h + "/configuration.nix")
      ];
    };

  toAttrs =
    f:
    builtins.listToAttrs (
      map (h: {
        inherit (h) name;
        value = f h;
      }) hosts
    );

  rawHive = {
    meta = {
      nixpkgs = mkPkgs defaultSystem;
      inherit nodeNixpkgs nodeSpecialArgs;
      allowApplyAll = false;
      specialArgs = {
        inherit inputs self;
        pkgsUnstable = mkPkgsUnstable defaultSystem;
        hostUses = { };
      };
    };
  }
  // toAttrs mkNode;

  # Fast path for Colmena's deployment metadata.
  #
  # Colmena's default `deploymentConfig` is:
  #   mapAttrs (_: node: node.config.deployment) nodes
  # which forces a full NixOS module evaluation for every host. For this fleet,
  # deployment values are deliberately restricted to meta.nix plus fixed Colmena
  # defaults, so we can construct the same shape directly from inventory data.
  #
  # IMPORTANT: If you start setting extra `deployment.*` options in host modules
  # instead of meta.nix, update this fast path or remove the override. Otherwise
  # Colmena's SSH target/tag discovery will not see those module-level changes.
  fastDeploymentConfig = toAttrs (h: {
    allowLocalDeployment = true;
    buildOnTarget = false;
    keys = { };
    privilegeEscalationCommand = [
      "sudo"
      "-H"
      "--"
    ];
    replaceUnknownProfiles = true;
    sshOptions = [ ];
    tags = h.meta.deployment.tags;
    targetHost = h.meta.deployment.targetHost;
    targetPort = h.meta.deployment.sshPort;
    targetUser = h.meta.deployment.sshUser;
  });

  colmenaHive = inputs.colmena.lib.makeHive rawHive;
in
{
  flake = {
    # Keep the real Colmena hive, but replace the expensive deployment metadata
    # accessors with inventory-only versions. Full builds/evals still go through
    # Colmena's normal `nodes`, `toplevel`, `evalSelected`, etc.
    colmenaHive = colmenaHive // {
      deploymentConfig = fastDeploymentConfig;
      deploymentConfigSelected =
        names: inputs.nixpkgs.lib.filterAttrs (name: _: builtins.elem name names) fastDeploymentConfig;
    };

    nixosConfigurations = toAttrs mkSystem;
  };
}
