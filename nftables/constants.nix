# Shared network constants for use in host firewall configs.
#
# These are plain Nix values — no DSL dependency — so they can also be used
# outside firewall rules (e.g. access-control lists, BIRD configs, allowlists).
#
# In rules, pair with the nftablesHelpers.acceptFromNetworks helper:
#   interfaces.backbone.rules =
#     nftablesHelpers.acceptFromNetworks nftablesConstants.privilegedNetworks;
#
# For destination-address rules, use DSL directly:
#   [(is.eq ip.daddr (set (map cidr nftablesConstants.ownPrefixes.v4))) return]
{
  # Networks that are trusted for full management access to all routers.
  # Covers the admin segment, infra segment, VPN road-warrior clients,
  # and VPN-GW clients.
  privilegedNetworks = {
    v4 = [
      "10.0.0.0/24"
      "10.0.5.0/24"
      "10.21.21.0/24"
      "10.21.22.1/32"
      "10.21.22.2/32"
      "10.21.22.3/32"
    ];
    v6 = [
      "fdb3:2b92:1088::3/128"
      "fdb3:2b92:1088::2/128"
      "fdb3:2b92:1088::1/128"
      "2a14:47c0:e002::/64"
      "2a14:47c0:e002:5::/64"
      "2a14:47c0:e002:2121::/64"
    ];
  };

  # Publicly announced IP space for AS213579.
  # Used in NAT rules (don't masquerade own space) and DNS source allowlists.
  AS213579Prefixes = {
    v4 = [
      "185.140.54.0/24"
    ];
    v6 = [
      "2a14:47c0:e001::/48"
      "2a14:47c0:e002::/48"
      "2a14:47c0:e048::/48"
    ];
  };

  # Own DN42 address space for AS213579.
  # Used in NAT rules (don't NAT already-DN42 sources) and forwarding filters.
  ownDN42Prefixes = {
    v4 = [ "172.22.169.64/26" ];
    v6 = [ "fdad:f45e:feef::/48" ];
  };

  # iBGP route reflectors for the home site.
  # Used in bgpPeers rules and BIRD neighbor configs.
  homeRouteReflectors = {
    v6 = [
      "2a14:47c0:e002:254::150"
      "2a14:47c0:e002:254::151"
    ];
  };

  # Acceptable ICMP / ICMPv6 type lists.
  # Pass to nftablesHelpers.acceptIcmpTypes:
  #   floatingRules = nftablesHelpers.acceptIcmpTypes
  #     nftablesConstants.icmpTypes.v4
  #     nftablesConstants.icmpTypes.v6Router;
  icmpTypes = {
    # Diagnostically necessary ICMPv4 types.
    v4 = [
      "echo-request"
      "destination-unreachable"
      "time-exceeded"
      "parameter-problem"
    ];

    # Diagnostically necessary ICMPv6 types including NDP (for hosts).
    v6 = [
      "echo-request"
      "destination-unreachable"
      "packet-too-big"
      "time-exceeded"
      "parameter-problem"
      "nd-neighbor-solicit"
      "nd-neighbor-advert"
    ];

    # ICMPv6 types extended for routers running radvd (adds RS + RA).
    v6Router = [
      "echo-request"
      "destination-unreachable"
      "packet-too-big"
      "time-exceeded"
      "parameter-problem"
      "nd-neighbor-solicit"
      "nd-neighbor-advert"
      "nd-router-solicit"
      "nd-router-advert"
    ];
  };

  # Internal service host addresses, namespaced by site.
  # Use directly in ip daddr / ip6 daddr expressions.
  services = {
    home = {
      # Recursive DNS resolvers.
      dns = {
        v4 = [ "10.10.10.10" ];
        v6 = [
          "2a14:47c0:e002:1010::10"
          "2a14:47c0:e002:1010::2"
        ];
      };

      # ChronoLease — combined DHCP + NTP server.
      ntp = {
        v4 = [ "10.10.10.20" ];
        v6 = [ "2a14:47c0:e002:1010::1020" ];
      };
      dhcp = {
        v4 = [ "10.10.10.20" ];
        v6 = [ "2a14:47c0:e002:1010::1020" ];
      };
    };
  };
}
