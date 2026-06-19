# Shared notnft DSL helpers for use in host firewall configs.
#
# All helpers return a list of rules: [[stmt...] [stmt...] ...]
# Concatenate with ++ to compose:
#   interfaces.wan0.rules =
#     helpers.acceptIcmpDefault
#     ++ helpers.acceptTcp [ 22 443 ]
#     ++ [[(is.eq ip.saddr "10.0.0.0/8") accept]]
#     ++ [[drop]];
{ notnft }:
with notnft.dsl;
with payload;
let
  # Internal IPv4 helpers — not exported.
  parseCidr4 =
    cidrStr:
    let
      parts = builtins.match "([0-9.]+)/([0-9]+)" cidrStr;
    in
    {
      addr = builtins.elemAt parts 0;
      len = builtins.fromJSON (builtins.elemAt parts 1);
    };
  intToIpv4 =
    n:
    let
      b0 = n / 16777216;
      r0 = n - b0 * 16777216;
      b1 = r0 / 65536;
      r1 = r0 - b1 * 65536;
      b2 = r1 / 256;
      b3 = r1 - b2 * 256;
    in
    "${toString b0}.${toString b1}.${toString b2}.${toString b3}";
  # Host-bit mask for a /len prefix: len=16 → "0.0.255.255", len=24 → "0.0.0.255".
  hostMask4 =
    len:
    let
      pow2 = n: if n == 0 then 1 else 2 * pow2 (n - 1);
    in
    intToIpv4 (pow2 (32 - len) - 1);
in
rec {

  # ── conntrack ────────────────────────────────────────────────────────────────

  # Accept established/related, drop invalid.
  # Put this near the top of floating or a per-interface chain.
  conntrack = [
    [
      (vmap ct.state {
        established = accept;
        related = accept;
        invalid = drop;
      })
    ]
  ];

  # ── loopback ─────────────────────────────────────────────────────────────────

  # Accept all loopback traffic.
  acceptLo = [
    [
      (is.eq meta.iifname "lo")
      accept
    ]
  ];

  # ── ICMP ─────────────────────────────────────────────────────────────────────

  # Accept all ICMP and ICMPv6 (inet tables).
  acceptIcmp = [
    [
      (is.eq ip.protocol (f: f.icmp))
      accept
    ]
    [
      (is.eq ip6.nexthdr (f: f.ipv6-icmp))
      accept
    ]
  ];

  # Accept only specific ICMP type lists.
  #   acceptIcmpTypes
  #     [ "echo-request" "destination-unreachable" "time-exceeded" ]
  #     [ "echo-request" "destination-unreachable" "packet-too-big" "time-exceeded" ]
  acceptIcmpTypes = v4types: v6types: [
    [
      (is.eq ip.protocol (f: f.icmp))
      (is.eq icmp.type (set v4types))
      accept
    ]
    [
      (is.eq ip6.nexthdr (f: f.ipv6-icmp))
      (is.eq icmpv6.type (set v6types))
      accept
    ]
  ];

  # Sane default: only diagnostically necessary ICMP types.
  acceptIcmpDefault =
    acceptIcmpTypes
      [ "echo-request" "destination-unreachable" "time-exceeded" "parameter-problem" ]
      [
        "echo-request"
        "destination-unreachable"
        "packet-too-big"
        "time-exceeded"
        "parameter-problem"
        "nd-neighbor-solicit"
        "nd-neighbor-advert"
      ];

  # Rate-limited ICMP accept followed by a blanket ICMP drop.
  # Typically used on WAN ingress before the default-drop policy kicks in.
  #   interfaces.wan0.rules = icmpRateLimit 20 ++ [[drop]];
  icmpRateLimit = rate: [
    [
      (is.eq ip.protocol (f: f.icmp))
      (limit {
        inherit rate;
        per = f: f.second;
      })
      accept
    ]
    [
      (is.eq ip6.nexthdr (f: f.ipv6-icmp))
      (limit {
        inherit rate;
        per = f: f.second;
      })
      accept
    ]
    [
      (is.eq ip.protocol (f: f.icmp))
      drop
    ]
    [
      (is.eq ip6.nexthdr (f: f.ipv6-icmp))
      drop
    ]
  ];

  # ── MSS clamping ─────────────────────────────────────────────────────────────

  # MSS clamping for a given EGRESS interface pattern.
  # Typically goes in extraForwardRules.
  # mss6 defaults to mss4 - 20 (IPv6 header is 20 bytes larger than IPv4).
  #
  # Examples:
  #   extraForwardRules = mssClamp { iface = "ppp0"; mss4 = 1452; mss6 = 1432; }
  #                    ++ mssClamp { iface = "wg*";  mss4 = 1392; mss6 = 1372; };
  # mtu is the interface MTU; mss4/mss6 can be given explicitly instead.
  # mss4 = mtu - 40 (20-byte IPv4 header + 20-byte TCP header)
  # mss6 = mtu - 60 (40-byte IPv6 header + 20-byte TCP header)
  mssClamp =
    {
      iface,
      mtu ? null,
      mss4 ? (if mtu != null then mtu - 40 else 1452),
      mss6 ? (if mtu != null then mtu - 60 else mss4 - 20),
    }:
    [
      [
        (is.eq meta.oifname iface)
        (is.eq ip.protocol (f: f.tcp))
        (is tcp.flags (f: f.syn))
        (mangle tcpOpt.maxseg.size mss4)
      ]
      [
        (is.eq meta.oifname iface)
        (is.eq ip6.nexthdr (f: f.tcp))
        (is tcp.flags (f: f.syn))
        (mangle tcpOpt.maxseg.size mss6)
      ]
    ];

  # ── BGP / BFD ────────────────────────────────────────────────────────────────

  # Accept BGP (179/tcp) and BFD (3784/udp) from explicit IPv4 and/or IPv6 peers.
  # Pass [] to skip a family.
  bgpPeers =
    peers4: peers6:
    (
      if peers4 != [ ] then
        [
          [
            (is.eq ip.saddr (set peers4))
            (is.eq tcp.dport 179)
            accept
          ]
          [
            (is.eq ip.saddr (set peers4))
            (is.eq udp.dport 3784)
            accept
          ]
        ]
      else
        [ ]
    )
    ++ (
      if peers6 != [ ] then
        [
          [
            (is.eq ip6.saddr (set peers6))
            (is.eq tcp.dport 179)
            accept
          ]
          [
            (is.eq ip6.saddr (set peers6))
            (is.eq udp.dport 3784)
            accept
          ]
        ]
      else
        [ ]
    );

  # Accept BGP + BFD arriving on any of the listed interfaces.
  bgpIfaces = ifaces: [
    [
      (is.eq meta.iifname (set ifaces))
      (is.eq tcp.dport 179)
      accept
    ]
    [
      (is.eq meta.iifname (set ifaces))
      (is.eq udp.dport 3784)
      accept
    ]
  ];

  # Accept BGP from link-local IPv6 (common for iBGP over direct links).
  bgpLinkLocal = [
    [
      (is.eq ip6.saddr (cidr "fe80::/10"))
      (is.eq tcp.dport 179)
      accept
    ]
  ];

  # ── WireGuard ────────────────────────────────────────────────────────────────

  # Accept WireGuard handshake UDP on the given port list.
  acceptWg = ports: [
    [
      (is.eq udp.dport (set ports))
      accept
    ]
  ];

  # ── TCP / UDP port helpers ───────────────────────────────────────────────────

  # Accept TCP on the given ports.
  acceptTcp = ports: [
    [
      (is.eq tcp.dport (set ports))
      accept
    ]
  ];

  # Accept UDP on the given ports.
  acceptUdp = ports: [
    [
      (is.eq udp.dport (set ports))
      accept
    ]
  ];

  # Accept TCP and UDP on the same ports (e.g. DNS port 53).
  acceptTcpUdp = ports: [
    [
      (is.eq ip.protocol (
        f:
        with f;
        set [
          tcp
          udp
        ]
      ))
      (is.eq th.dport (set ports))
      accept
    ]
    [
      (is.eq ip6.nexthdr (
        f:
        with f;
        set [
          tcp
          udp
        ]
      ))
      (is.eq th.dport (set ports))
      accept
    ]
  ];

  # ── Network sets ─────────────────────────────────────────────────────────

  # Accept all traffic from a { v4 = [cidr...]; v6 = [cidr...]; } networks attrset.
  # Designed to pair with constants from nftablesConstants.
  #   interfaces.backbone.rules =
  #     helpers.acceptFromNetworks nftablesConstants.privilegedNetworks;
  acceptFromNetworks =
    networks:
    (
      if (networks.v4 or [ ]) != [ ] then
        [
          [
            (is.eq ip.saddr (set (map cidr (networks.v4 or [ ]))))
            accept
          ]
        ]
      else
        [ ]
    )
    ++ (
      if (networks.v6 or [ ]) != [ ] then
        [
          [
            (is.eq ip6.saddr (set (map cidr (networks.v6 or [ ]))))
            accept
          ]
        ]
      else
        [ ]
    );

  # ── NAT ──────────────────────────────────────────────────────────────────────

  # Masquerade traffic leaving `wan` that arrived on `lan` (inet tables).
  masqLanToWan = lan: wan: [
    [
      (is.eq meta.iifname lan)
      (is.eq meta.oifname wan)
      masquerade
    ]
  ];

  # One-to-one NAT (NETMAP) between two equal-size IPv4 prefix ranges.
  #
  # DNAT (prerouting + output): packets marked with `mark` have daddr remapped
  #   virtualCidr → realCidr, preserving host bits via bitwise mask.
  # SNAT (postrouting): return packets arriving via `iifname` have saddr remapped
  #   realCidr → virtualCidr.
  #
  # Returns { prerouting, output, postrouting } rule lists.
  # Concatenate each into the corresponding nat.extra*Rules with ++.
  #
  # Example:
  #   let t = helpers.netmapNat {
  #     mark = 258; virtualCidr = "10.31.0.0/16";
  #     realCidr = "192.168.0.0/16"; iifname = "papa_wg";
  #   };
  #   in {
  #     nat.extraPreroutingRules = t.prerouting;
  #     nat.extraOutputRules     = t.output;
  #     nat.extraPostroutingRules = t.postrouting ++ [...];
  #   }
  netmapNat =
    {
      mark, # fwmark integer matching pbr.marks
      virtualCidr, # "A.B.C.D/N" — virtual address space seen by local clients
      realCidr, # "A.B.C.D/N" — real addresses inside the tunnel (same /N)
      iifname, # ingress interface name for the reverse SNAT (e.g. "papa_wg")
    }:
    let
      virt = parseCidr4 virtualCidr;
      real = parseCidr4 realCidr;
      mask = hostMask4 virt.len;
      fwdDnat = dnat { addr = bit."|" (bit.and ip.daddr mask) real.addr; };
      revSnat = snat { addr = bit."|" (bit.and ip.saddr mask) virt.addr; };
    in
    {
      prerouting = [
        [
          (is.eq meta.mark mark)
          fwdDnat
        ]
      ];
      output = [
        [
          (is.eq meta.mark mark)
          fwdDnat
        ]
      ];
      postrouting = [
        [
          (is.eq meta.iifname iifname)
          revSnat
        ]
      ];
    };

  # One-to-one NAT (NETMAP) with static source NAT for tunnel egress.
  # Extends netmapNat with an additional `snat to srcAddr` rule in postrouting,
  # applied to all traffic leaving via `oifname`. Use when the tunnel peer
  # requires packets to arrive from a specific source address.
  #
  # Example:
  #   let t = helpers.netmapNatWithSnat {
  #     mark = 258; virtualCidr = "10.31.0.0/16"; realCidr = "192.168.0.0/16";
  #     iifname = "papa_wg"; oifname = "papa_wg"; srcAddr = "192.168.178.201";
  #   };
  netmapNatWithSnat =
    {
      mark,
      virtualCidr,
      realCidr,
      iifname,
      oifname, # egress interface for static SNAT
      srcAddr, # source address to stamp on outbound packets (e.g. "192.168.178.201")
    }:
    let
      base = netmapNat {
        inherit
          mark
          virtualCidr
          realCidr
          iifname
          ;
      };
    in
    base
    // {
      postrouting = [
        [
          (is.eq meta.oifname oifname)
          (snat { addr = srcAddr; })
        ]
      ]
      ++ base.postrouting;
    };

  # ── PBR ──────────────────────────────────────────────────────────────────────

  # Set fwmark on packets destined for dstCidr. Returns a single-rule list
  # suitable for use in pbr.extraPreroutingRules / pbr.extraOutputRules.
  #
  # Example (equivalent to a pbr.marks entry):
  #   pbr.extraPreroutingRules = pbrMark 0x101 "10.30.0.0/24";
  pbrMark = mark: dstCidr: [
    [
      (is.eq ip.daddr (cidr dstCidr))
      (mangle meta.mark mark)
    ]
  ];

}
