# Helper library passed to every host's `meta.nix` as `lib`.
#
# IMPORTANT: this is evaluated *offline* by the inventory generator
# (tools/inventory/collect-meta.nix) using builtins only — there is no
# nixpkgs / `lib` available here. Keep everything pure-builtins.
rec {
  # Deployment fields shared by every host. A host's meta.nix only needs to
  # override what actually differs (usually just targetHost + tags).
  defaults = {
    sshUser = "root";
    sshPort = 22;
    targetHost = null;
    tags = [ ];
  };

  # Build a host entry, merging the deployment defaults above.
  #
  #   lib.mkHost {
  #     targetHost = "10.0.10.3";
  #     tags = [ "netbox" "server" ];
  #     dependencies = [ "server.home.dns" "localdns" ];
  #     dependencyGroupMemberships = [ "home_route_reflectors" ];
  #     dependencies = [ "server.home.dns" "#home_route_reflectors" ];
  #     system = "aarch64-linux";
  #   }
  #
  # `system`, `dependencies` (a list of host keys/tags and `#group` references),
  # `dependencyGroupMemberships` (groups this host belongs to), explicit
  # `dependencyGroups`, and `sshPublicKey(s)` are lifted out of the deployment
  # attrset; everything else is treated as a deployment override.
  mkHost = args: {
    deployment =
      defaults
      // (builtins.removeAttrs args [
        "system"
        "dependencies"
        "dependencyGroups"
        "dependencyGroupMemberships"
        "sshPublicKey"
        "sshPublicKeys"
      ]);
    system = args.system or "x86_64-linux";
    dependencies = args.dependencies or [ ];
    dependencyGroups = args.dependencyGroups or [ ];
    dependencyGroupMemberships = args.dependencyGroupMemberships or [ ];
    sshPublicKeys = args.sshPublicKeys or (if args ? sshPublicKey then [ args.sshPublicKey ] else [ ]);
  };

  # Role-flavoured aliases. Currently identical to mkHost (tags stay explicit),
  # but give call sites a self-documenting name and a single place to hook in
  # role-specific defaults later.
  mkServer = mkHost;
  mkRouter = mkHost;
  mkDesktop = mkHost;

  # --- address helpers -----------------------------------------------------
  # Compose addresses from a prefix + host part so meta.nix can share the same
  # numbering as a host's network.nix instead of hard-coding a literal.
  #   lib.ip4 "10.0.10" 3            => "10.0.10.3"
  #   lib.ip6 "2a14:47c0:e002:10" 3  => "2a14:47c0:e002:10::3"
  ip4 = prefix: part: "${prefix}.${toString part}";
  ip6 = prefix: part: "${prefix}::${toString part}";
}
