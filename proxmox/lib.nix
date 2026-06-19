# proxmox/lib.nix — helpers for writing proxmox.nix VM specs.
#
# Imported with `{ self }` so the from-host helpers can read a machine's real
# NixOS network configuration out of `self.nixosConfigurations`.
#
# Usage in a proxmox.nix that accepts an argument:
#
#   { lib }:
#   lib.profiles.small // {
#     vmid     = null;
#     node     = "my-node";
#     template = 10002;
#     net0     = lib.mkNet "vmbr0" {};
#     ipconfig0 = lib.mkIpConfig { ip = "10.0.1.5/24"; gw = "10.0.1.1"; };
#     # …or derive ipconfig0 from the host's NixOS network config:
#     ipconfig0 = lib.mkIpConfigFromHost { };   # machine defaults to this host
#     boot     = lib.mkBoot "virtio0";
#     sshkeys  = lib.mkSshKeys [ "ssh-ed25519 AAAA..." ];
#   }
#
# Files that take no argument continue to work unchanged.

{
  self ? null,
}:
let
  # mkLib builds the helper set with `defaultHost` baked in, so a per-host lib
  # (see flake-part.nix `withHost`) lets `mkIpConfigFromHost { }` default to the
  # host its proxmox.nix lives under. The top-level export binds no host.
  mkLib =
    defaultHost:
    let
      optStr = cond: s: if cond then [ s ] else [ ];

      # ── Network ───────────────────────────────────────────────────────────────────
      # mkNet bridge {} → "virtio,bridge=vmbr0"
      # mkNet bridge { model = "e1000"; firewall = true; tag = 100; rate = 100; }
      #   → "e1000,bridge=vmbr0,firewall=1,tag=100,rate=100"
      # mkNet bridge { mac = "bc:24:11:00:00:01"; }
      #   → "virtio=bc:24:11:00:00:01,bridge=vmbr0"
      mkNet =
        bridge:
        {
          model ? "virtio",
          mac ? null, # pin the NIC's MAC (lowercase hex, colon-separated)
          firewall ? false,
          tag ? null, # VLAN tag (int)
          rate ? null, # rate limit in MB/s (int)
          queues ? null, # number of packet queues (int)
          mtu ? null, # override MTU (int)
          linkDown ? null, # administratively down when set (0/1)
        }:
        # When mac is null no MAC is emitted: proxmox-sync strips the PVE-assigned
        # MAC before comparing netN and re-injects it on write, so the VM keeps its
        # existing MAC. Pin mac to fix the MAC across VM re-creation — needed where a
        # guest renames interfaces by MAC (lh.networking.staticInterfaceNames).
        builtins.concatStringsSep "," (
          [ "${model}${if mac != null then "=${mac}" else ""},bridge=${bridge}" ]
          ++ optStr firewall "firewall=1"
          ++ optStr (tag != null) "tag=${builtins.toString tag}"
          ++ optStr (rate != null) "rate=${builtins.toString rate}"
          ++ optStr (queues != null) "queues=${builtins.toString queues}"
          ++ optStr (mtu != null) "mtu=${builtins.toString mtu}"
          ++ optStr (linkDown != null) "link_down=${builtins.toString linkDown}"
        );

      # ── IP config ─────────────────────────────────────────────────────────────────
      # mkIpConfig {}                                   → "ip=dhcp"
      # mkIpConfig { ip = "10.0.0.5/24"; gw = "..."; } → "ip=10.0.0.5/24,gw=10.0.0.1"
      # mkIpConfig { ip = "dhcp"; ip6 = "dhcp6"; }     → "ip=dhcp,ip6=dhcp6"
      mkIpConfig =
        {
          ip ? "dhcp",
          gw ? null,
          ip6 ? null,
          gw6 ? null,
        }:
        builtins.concatStringsSep "," (
          [ "ip=${ip}" ]
          ++ optStr (gw != null) "gw=${gw}"
          ++ optStr (ip6 != null) "ip6=${ip6}"
          ++ optStr (gw6 != null) "gw6=${gw6}"
        );

      # ── IP config from a host's NixOS config ───────────────────────────────────────
      # Mirrors the dns `…FromMachine` helpers: instead of hardcoding the address and
      # gateway, read them straight out of the host's NixOS network configuration so the
      # cloud-init ipconfig can never drift from what the guest is actually configured for.
      #
      #   mkIpConfigFromHost { }                          # machine defaults to this host
      #   mkIpConfigFromHost { machine = "server.home.dns"; }
      #   mkIpConfigFromHost { interface = "ens18"; ipv6 = false; }
      #
      # `machine` is the dotted nixosConfigurations key (same key proxmox-sync uses).
      # `interface` selects a single systemd.network network / networking.interfaces
      # entry; when null, every interface on the host is considered.
      hasColon = s: builtins.isString s && builtins.match ".*:.*" s != null;
      isV4Addr = s: builtins.isString s && builtins.match "[0-9][0-9.]*(/[0-9]+)?" s != null;
      isV6Addr = hasColon;
      firstOr = default: xs: if xs == [ ] then default else builtins.head xs;

      # Pull the address (kept with its prefix length) and gateway lists for the
      # selected interface(s) from both the systemd-networkd and the legacy
      # networking.interfaces representations.
      hostAddrsAndGws =
        { machine, interface }:
        let
          configs =
            if self != null then
              self.nixosConfigurations or { }
            else
              throw "proxmox lib: mkIpConfigFromHost needs `self`; pass it via `import ./proxmox/lib.nix { inherit self; }`.";
          cfg =
            if builtins.hasAttr machine configs then
              configs.${machine}.config
            else
              throw "proxmox lib.mkIpConfigFromHost: machine '${machine}' not found in self.nixosConfigurations.";

          ifaceMatches = name: matchName: interface == null || name == interface || matchName == interface;

          # systemd-networkd: address = [ "10.0.0.5/24" … ]; gateway = [ "10.0.0.1" … ]
          networks = cfg.systemd.network.networks or { };
          sdNets = builtins.filter (n: ifaceMatches n ((networks.${n}.matchConfig or { }).Name or null)) (
            builtins.attrNames networks
          );
          sdAddrs = builtins.concatLists (builtins.map (n: networks.${n}.address or [ ]) sdNets);
          sdGws = builtins.concatLists (builtins.map (n: networks.${n}.gateway or [ ]) sdNets);

          # legacy networking.interfaces.<name>.ipv{4,6}.addresses = [ { address; prefixLength; } ]
          legacyIfaces = cfg.networking.interfaces or { };
          legNames = builtins.filter (n: ifaceMatches n n) (builtins.attrNames legacyIfaces);
          legAddrsOf =
            fam:
            builtins.concatLists (
              builtins.map (
                n:
                builtins.map (a: "${a.address}/${builtins.toString a.prefixLength}") (
                  (legacyIfaces.${n}.${fam} or { }).addresses or [ ]
                )
              ) legNames
            );
          legAddrs = legAddrsOf "ipv4" ++ legAddrsOf "ipv6";
          legGws = builtins.filter (g: g != null) [
            (cfg.networking.defaultGateway.address or cfg.networking.defaultGateway or null)
            (cfg.networking.defaultGateway6.address or cfg.networking.defaultGateway6 or null)
          ];
        in
        {
          addrs = sdAddrs ++ legAddrs;
          gws = sdGws ++ legGws;
        };

      # `machine` defaults to the host this proxmox.nix lives under: flake-part.nix
      # binds it per-VM via `lib.withHost`, so `mkIpConfigFromHost { }` Just Works.
      mkIpConfigFromHost =
        {
          machine ? defaultHost,
          interface ? null,
          ipv4 ? true,
          ipv6 ? true,
        }:
        let
          machine' =
            if machine != null then
              machine
            else
              throw "proxmox lib.mkIpConfigFromHost: no `machine` given and no host bound; pass `machine = \"<dotted.host>\"`.";
          inherit
            (hostAddrsAndGws {
              machine = machine';
              inherit interface;
            })
            addrs
            gws
            ;
          v4addr = builtins.filter isV4Addr addrs;
          v6addr = builtins.filter isV6Addr addrs;
          v4gw = builtins.filter (g: !hasColon g) gws;
          v6gw = builtins.filter hasColon gws;
        in
        mkIpConfig {
          ip = if ipv4 then firstOr "dhcp" v4addr else "dhcp";
          gw = if ipv4 then firstOr null v4gw else null;
          ip6 = if ipv6 then firstOr null v6addr else null;
          gw6 = if ipv6 then firstOr null v6gw else null;
        };

      # ── Boot order ────────────────────────────────────────────────────────────────
      # mkBoot "virtio0"        → "order=virtio0"
      # mkBoot "virtio0;net0"   → "order=virtio0;net0"
      mkBoot = disk: "order=${disk}";

      # ── SSH keys ──────────────────────────────────────────────────────────────────
      # mkSshKeys [ "ssh-ed25519 AAA..." "ssh-rsa AAAB..." ]
      #   → "ssh-ed25519 AAA...\nssh-rsa AAAB..."
      mkSshKeys = keys: builtins.concatStringsSep "\n" keys;

      # ── Disk ──────────────────────────────────────────────────────────────────────
      # mkDisk "local-lvm" "20G" → "local-lvm:20G"
      # Useful when declaring a new disk inline rather than referencing a clone path.
      mkDisk = storage: size: "${storage}:${size}";
    in
    {
      # ── Profiles ──────────────────────────────────────────────────────────────
      # Import by name instead of a deep relative path.
      profiles = {
        small = import ./profiles/small-vm.nix;
        medium = import ./profiles/medium-vm.nix;
        big = import ./profiles/big-vm.nix;
        legacy = import ./profiles/legacy-vm.nix;
      };

      # Return a copy of this lib with `host` as the default machine for the
      # *FromHost helpers. flake-part.nix calls this per proxmox.nix.
      withHost = mkLib;

      inherit
        mkNet
        mkIpConfig
        mkIpConfigFromHost
        mkBoot
        mkSshKeys
        mkDisk
        ;
    };
in
mkLib null
