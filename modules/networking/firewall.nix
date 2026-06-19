{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.lh.firewall;

  # VRF customer NAT zones (see lh.firewall.nat.vrfZones). Plain data shared
  # between the ruleset generator and the routing/ip-rule systemd service.
  inherit (cfg.nat) vrfZones;
  vrfZoneList = lib.attrValues vrfZones;
  hasVrfZones = vrfZones != { };

  # fwmark→table ip rules and per-VRF default routes, one block per zone.
  vrfV4RoutingScript = lib.concatStringsSep "\n" (
    lib.imap0 (
      i: z:
      let
        prio = toString (cfg.nat.vrfRulePriority + i);
        mark = toString z.mark;
        table = toString z.table;
        mkDefault =
          fam: r:
          "ip -${fam} route replace default via ${r.via} dev ${r.dev}${lib.optionalString r.onLink " onlink"} table ${table}";
      in
      lib.concatStringsSep "\n" (
        [
          "ip -4 rule del fwmark ${mark} table ${table} 2>/dev/null || true"
          "ip -4 rule add fwmark ${mark} table ${table} priority ${prio}"
        ]
        ++ lib.optional (z.defaultRoute.v4 != null) (mkDefault "4" z.defaultRoute.v4)
        ++ lib.optional (z.defaultRoute.v6 != null) (mkDefault "6" z.defaultRoute.v6)
      )
    ) vrfZoneList
  );

  # IPv6 customer prefixes are globally routed (not NAT'd), but the customer
  # interface is VRF-enslaved, so a plain `via <iface>` route in the main table is
  # rejected. Instead, per prefix: a link route in the VRF table (ND-delivers to
  # the customer) plus an `iif <wan> to <prefix> lookup <vrfTable>` ip rule that
  # steers WAN-ingress traffic into the VRF. The `iif <wan>` qualifier keeps
  # inter-zone isolation intact — a customer→customer packet stays in its own VRF
  # table (l3mdev) and is dropped on the WAN hairpin by the firewall.
  vrfV6Pairs = lib.concatMap (
    z: lib.optionals (z.ingressInterfaces != [ ]) (map (p: { inherit z p; }) z.prefixes.v6)
  ) vrfZoneList;

  vrfV6RoutingScript = lib.concatStringsSep "\n" (
    lib.imap0 (
      j:
      { z, p }:
      let
        table = toString z.table;
        linkIface = builtins.head z.ingressInterfaces;
        prio = toString (cfg.nat.vrfRulePriority + 100 + j);
      in
      lib.concatStringsSep "\n" (
        # The link route is skipped when BIRD (lh.router.bird.vrfs) originates the
        # customer prefix into the VRF table instead — the iif-WAN steering rule is
        # always needed regardless of who owns the route.
        lib.optional z.manageV6Routes "ip -6 route replace ${p} dev ${linkIface} table ${table}"
        ++ [
          "ip -6 rule del iif ${z.wanInterface} to ${p} table ${table} 2>/dev/null || true"
          "ip -6 rule add iif ${z.wanInterface} to ${p} table ${table} priority ${prio}"
        ]
      )
    ) vrfV6Pairs
  );

  vrfRoutingScript = lib.concatStringsSep "\n" (
    lib.filter (s: s != "") [
      vrfV4RoutingScript
      vrfV6RoutingScript
    ]
  );

  # notnft chains use a variadic functor pattern: each rule is a separate call.
  # This helper folds a list of rules into the chain builder.
  chainFromRules = base: rules: builtins.foldl' (acc: acc) base rules;

  policyFn = p: if p == "drop" then f: f.drop else f: f.accept;

  generatedRuleset =
    with config.notnft.dsl;
    with payload;
    let

      conntrackRule =
        if cfg.conntrack == "full" || cfg.conntrack == "statelessForward" then
          [
            (vmap ct.state {
              established = accept;
              related = accept;
              invalid = drop;
            })
          ]
        else if cfg.conntrack == "stateless" then
          [
            (vmap ct.state {
              established = accept;
              related = accept;
            })
          ]
        else
          null;

      # When statelessForward: notrack all forwarded (non-local-destination) traffic
      # in the raw prerouting chain so that conntrack never sees it. The filter_common
      # conntrack rule (including the invalid drop) then only fires for locally-destined
      # traffic, which is always fully tracked.
      rawTableAttrs = lib.optionalAttrs (cfg.conntrack == "statelessForward") {
        raw = add table.inet {
          prerouting =
            chainFromRules
              (add chain {
                type = f: f.filter;
                hook = f: f.prerouting;
                prio = f: f.raw;
                policy = f: f.accept;
              })
              [
                [
                  (is.ne (fib (f: with f; [ daddr ]) (f: f.type)) (f: f.local))
                  notrack
                ]
              ];
        };
      };

      loRule = [
        (is.eq meta.iifname "lo")
        accept
      ];

      ifaceJumps = map (name: [
        (is.eq meta.iifname name)
        (jump "iface_${name}")
      ]) (lib.attrNames cfg.interfaces);

      filterCommonRules =
        lib.optional (conntrackRule != null) conntrackRule
        ++ [ loRule ]
        ++ lib.optional (cfg.floatingRules != [ ]) [ (jump "floating") ]
        ++ ifaceJumps;

      floatingChainAttr = lib.optionalAttrs (cfg.floatingRules != [ ]) {
        floating = chainFromRules (add chain) cfg.floatingRules;
      };

      ifaceChainAttrs = lib.mapAttrs' (
        name: icfg: lib.nameValuePair "iface_${name}" (chainFromRules (add chain) icfg.rules)
      ) cfg.interfaces;

      # Interfaces that have inputOnlyRules get a separate chain only reachable
      # from the input hook — never jumped to from filter_common (forward-safe).
      ifacesWithInputOnly = lib.filterAttrs (_: icfg: icfg.inputOnlyRules != [ ]) cfg.interfaces;

      ifaceInputChainAttrs = lib.mapAttrs' (
        name: icfg: lib.nameValuePair "iface_${name}_input" (chainFromRules (add chain) icfg.inputOnlyRules)
      ) ifacesWithInputOnly;

      ifaceInputJumps = map (name: [
        (is.eq meta.iifname name)
        (jump "iface_${name}_input")
      ]) (lib.attrNames ifacesWithInputOnly);

      # Interfaces that have forwardOnlyRules get a separate chain only reachable
      # from the forward hook — never jumped to from filter_common (input-safe).
      ifacesWithForwardOnly = lib.filterAttrs (_: icfg: icfg.forwardOnlyRules != [ ]) cfg.interfaces;

      ifaceForwardChainAttrs = lib.mapAttrs' (
        name: icfg:
        lib.nameValuePair "iface_${name}_forward" (chainFromRules (add chain) icfg.forwardOnlyRules)
      ) ifacesWithForwardOnly;

      ifaceForwardJumps = map (name: [
        (is.eq meta.iifname name)
        (jump "iface_${name}_forward")
      ]) (lib.attrNames ifacesWithForwardOnly);

      # ── NAT table generation ─────────────────────────────────────────────────

      natCfg = cfg.nat;

      # ── VRF customer NAT (generic, connmark-based reply steering) ─────────────
      # Each zone is one customer VRF behind a shared WAN. Overlapping/duplicate
      # customer prefixes are supported because the NAT reply path is disambiguated
      # via connmark rather than destination IP:
      #   ingress(customer iface) → ct mark set <mark>
      #   ingress(wan)            → meta mark set ct mark   (replies + inbound DNAT)
      #   ip rule fwmark <mark>   → VRF table               (routed back into the VRF)

      # set helper: avoid wrapping a single element in an anonymous set.
      ifSet = xs: if builtins.length xs == 1 then builtins.head xs else set xs;

      vrfWanIfaces = lib.unique (map (z: z.wanInterface) vrfZoneList);
      vrfAllV4 = lib.unique (lib.concatMap (z: z.prefixes.v4) vrfZoneList);
      vrfAllV6 = lib.unique (lib.concatMap (z: z.prefixes.v6) vrfZoneList);

      vrfProtoList =
        pf:
        if pf.protocol == "tcp_udp" then
          [
            "tcp"
            "udp"
          ]
        else
          [ pf.protocol ];

      # Match a (pre-DNAT) packet on the shared WAN port.
      vrfWanPortMatch =
        proto: port:
        if proto == "tcp" then
          [
            (is.eq ip.protocol (f: f.tcp))
            (is.eq tcp.dport port)
          ]
        else
          [
            (is.eq ip.protocol (f: f.udp))
            (is.eq udp.dport port)
          ];

      # inet prerouting (mangle prio): tag flows with their zone connmark, then
      # restore the connmark into the packet mark for everything arriving on WAN
      # (replies + inbound DNAT) so the fwmark ip rule can steer it into the VRF.
      vrfSteeringRules =
        map (z: [
          (is.eq meta.iifname (ifSet z.ingressInterfaces))
          (mangle ct.mark z.mark)
        ]) vrfZoneList
        ++ lib.concatMap (
          z:
          lib.concatMap (
            pf:
            map (
              proto:
              [ (is.eq meta.iifname z.wanInterface) ]
              ++ vrfWanPortMatch proto pf.wanPort
              ++ [ (mangle ct.mark z.mark) ]
            ) (vrfProtoList pf)
          ) z.portForwards
        ) vrfZoneList
        ++ lib.optional hasVrfZones [
          (is.eq meta.iifname (ifSet vrfWanIfaces))
          (mangle meta.mark ct.mark)
        ];

      vrfSteeringChainAttr = lib.optionalAttrs hasVrfZones {
        vrf_prerouting = chainFromRules (add chain {
          type = f: f.filter;
          hook = f: f.prerouting;
          prio = f: f.mangle;
          policy = f: f.accept;
        }) vrfSteeringRules;
      };

      # ip nat prerouting: DNAT shared WAN port → customer target.
      vrfDnatRules = lib.concatMap (
        z:
        lib.concatMap (
          pf:
          let
            dnatTarget =
              if pf.targetPort != null then
                dnat {
                  addr = pf.target;
                  port = pf.targetPort;
                }
              else
                dnat { addr = pf.target; };
          in
          map (
            proto: [ (is.eq meta.iifname z.wanInterface) ] ++ vrfWanPortMatch proto pf.wanPort ++ [ dnatTarget ]
          ) (vrfProtoList pf)
        ) z.portForwards
      ) vrfZoneList;

      # ip nat postrouting: masquerade this zone's egress (matched by connmark).
      vrfMasqRules = lib.concatMap (
        z:
        lib.optional z.masquerade [
          (is.eq meta.oifname z.wanInterface)
          (is.eq ct.mark z.mark)
          masquerade
        ]
      ) vrfZoneList;

      # forward: drop customer→customer. Matched on WAN egress + customer daddr,
      # which catches the hairpin a cross-zone packet takes (its own VRF table has
      # no route to the sibling prefix, so it falls to the WAN default route).
      vrfIsolationRules =
        lib.optional (vrfAllV4 != [ ]) [
          (is.eq meta.oifname (ifSet vrfWanIfaces))
          (is.eq ip.daddr (set (map cidr vrfAllV4)))
          drop
        ]
        ++ lib.optional (vrfAllV6 != [ ]) [
          (is.eq meta.oifname (ifSet vrfWanIfaces))
          (is.eq ip6.daddr (set (map cidr vrfAllV6)))
          drop
        ];

      # forward: allow customer→WAN, inbound port-forwards (post-DNAT), and
      # (optionally) inbound IPv6 to the customer's own prefixes.
      #
      # NOTE: under VRF the forward hook sees the VRF *master* device as iifname
      # (e.g. "vrf_leon"), not the physical customer interface. So customer→WAN is
      # matched on egress + connmark (the mark is set on physical ingress in
      # vrf_prerouting and is readable here), and inbound is matched on the WAN
      # iifname — the WAN is not VRF-enslaved, so its name is stable.
      vrfForwardRules =
        map (z: [
          (is.eq meta.oifname z.wanInterface)
          (is.eq ct.mark z.mark)
          accept
        ]) vrfZoneList
        ++ lib.concatMap (
          z:
          lib.concatMap (
            pf:
            let
              fwdPort = if pf.targetPort != null then pf.targetPort else pf.wanPort;
              fwdMatch =
                proto:
                if proto == "tcp" then
                  [
                    (is.eq ip.protocol (f: f.tcp))
                    (is.eq tcp.dport fwdPort)
                  ]
                else
                  [
                    (is.eq ip.protocol (f: f.udp))
                    (is.eq udp.dport fwdPort)
                  ];
            in
            map (
              proto:
              [
                (is.eq meta.iifname z.wanInterface)
                (is.eq ip.daddr pf.target)
              ]
              ++ fwdMatch proto
              ++ [ accept ]
            ) (vrfProtoList pf)
          ) z.portForwards
        ) vrfZoneList
        ++ lib.concatMap (
          z:
          lib.optional (z.allowV6Inbound && z.prefixes.v6 != [ ]) [
            (is.eq meta.iifname z.wanInterface)
            (is.eq ip6.daddr (set (map cidr z.prefixes.v6)))
            accept
          ]
        ) vrfZoneList;

      hasNatRules =
        natCfg.outbound != [ ]
        || natCfg.portForwards != [ ]
        || natCfg.oneToOne != [ ]
        || natCfg.extraPreroutingRules != [ ]
        || natCfg.extraPostroutingRules != [ ]
        || natCfg.extraOutputRules != [ ]
        || hasVrfZones;

      # Returns a list of rules (one for tcp/udp, two for tcp_udp).
      portForwardToRules =
        pf:
        let
          iifMatch = is.eq meta.iifname pf.iifname;
          dstAddrMatch = lib.optional (pf.destination != null) (is.eq ip.daddr (cidr pf.destination));
          portVal = if builtins.isList pf.dstPort then set pf.dstPort else pf.dstPort;
          dnatTarget =
            if pf.targetPort != null then
              dnat {
                addr = pf.target;
                port = pf.targetPort;
              }
            else
              dnat { addr = pf.target; };
          tcpRule = [
            iifMatch
          ]
          ++ dstAddrMatch
          ++ [
            (is.eq ip.protocol (f: f.tcp))
            (is.eq tcp.dport portVal)
            dnatTarget
          ];
          udpRule = [
            iifMatch
          ]
          ++ dstAddrMatch
          ++ [
            (is.eq ip.protocol (f: f.udp))
            (is.eq udp.dport portVal)
            dnatTarget
          ];
        in
        if pf.protocol == "tcp_udp" then
          [
            tcpRule
            udpRule
          ]
        else if pf.protocol == "tcp" then
          [ tcpRule ]
        else
          [ udpRule ];

      # prerouting: 1:1 DNAT first, then port forwards, then extras.
      preroutingRules =
        map (
          o:
          lib.optional (o.iifname != null) (is.eq meta.iifname o.iifname)
          ++ [
            (is.eq ip.daddr o.externalAddr)
            (dnat { addr = o.internalAddr; })
          ]
        ) natCfg.oneToOne
        ++ lib.concatMap portForwardToRules natCfg.portForwards
        ++ natCfg.extraPreroutingRules
        ++ vrfDnatRules;

      # Returns a single-element list so concatMap flattens correctly.
      outboundToRule = ob: [
        (
          [ (is.eq meta.oifname ob.oifname) ]
          ++ lib.optional (ob.source != null) (is.eq ip.saddr (cidr ob.source))
          ++ lib.optional (ob.destination != null) (is.eq ip.daddr (cidr ob.destination))
          ++ [ (if ob.type == "masquerade" then masquerade else snat { inherit (ob) addr; }) ]
        )
      ];

      # postrouting: 1:1 SNAT first (reverse of DNAT), then outbound NAT, then extras.
      postroutingRules =
        map (
          o:
          lib.optional (o.oifname != null) (is.eq meta.oifname o.oifname)
          ++ [
            (is.eq ip.saddr o.internalAddr)
            (snat { addr = o.externalAddr; })
          ]
        ) natCfg.oneToOne
        ++ lib.concatMap outboundToRule natCfg.outbound
        ++ natCfg.extraPostroutingRules
        ++ vrfMasqRules;

      hasNatRulesV6 = natCfg.extraPostroutingRulesV6 != [ ];

      nat6TableAttrs = lib.optionalAttrs hasNatRulesV6 {
        nat6 = add table { family = f: f.ip6; } {
          postrouting = chainFromRules (add chain {
            type = f: f.nat;
            hook = f: f.postrouting;
            prio = f: f.srcnat;
            policy = f: f.accept;
          }) natCfg.extraPostroutingRulesV6;
        };
      };

      natTableAttrs = lib.optionalAttrs hasNatRules {
        nat = add table { family = f: f.ip; } (
          {
            prerouting = chainFromRules (add chain {
              type = f: f.nat;
              hook = f: f.prerouting;
              prio = f: f.dstnat;
              policy = f: f.accept;
            }) preroutingRules;
            postrouting = chainFromRules (add chain {
              type = f: f.nat;
              hook = f: f.postrouting;
              prio = f: f.srcnat;
              policy = f: f.accept;
            }) postroutingRules;
          }
          // lib.optionalAttrs (natCfg.extraOutputRules != [ ]) {
            # DNAT for locally-originated traffic (router itself connecting to mapped ranges).
            output = chainFromRules (add chain {
              type = f: f.nat;
              hook = f: f.output;
              prio = f: f.dstnat;
              policy = f: f.accept;
            }) natCfg.extraOutputRules;
          }
        );
      };

      # ── PBR mangle table generation ──────────────────────────────────────────

      pbrCfg = cfg.pbr;

      hasPbrRules =
        pbrCfg.marks != [ ] || pbrCfg.extraPreroutingRules != [ ] || pbrCfg.extraOutputRules != [ ];

      # Each mark entry generates identical rules in both chains (forwarded + local traffic).
      pbrMarkRules = map (m: [
        (is.eq ip.daddr (cidr m.dstCidr))
        (mangle meta.mark m.mark)
      ]) pbrCfg.marks;

      pbrTableAttrs = lib.optionalAttrs hasPbrRules {
        mangle = add table { family = f: f.ip; } {
          prerouting = chainFromRules (add chain {
            type = f: f.filter;
            hook = f: f.prerouting;
            prio = -200;
            policy = f: f.accept;
          }) (pbrMarkRules ++ pbrCfg.extraPreroutingRules);
          output = chainFromRules (add chain {
            type = f: f.route;
            hook = f: f.output;
            prio = -200;
            policy = f: f.accept;
          }) (pbrMarkRules ++ pbrCfg.extraOutputRules);
        };
      };
    in
    ruleset (
      {
        firewall = add table.inet (
          floatingChainAttr
          // ifaceChainAttrs
          // ifaceInputChainAttrs
          // ifaceForwardChainAttrs
          // vrfSteeringChainAttr
          // {
            filter_common = chainFromRules (add chain) filterCommonRules;

            input = chainFromRules (add chain {
              type = f: f.filter;
              hook = f: f.input;
              prio = f: f.filter;
              policy = policyFn cfg.inputPolicy;
            }) (cfg.extraInputRules ++ ifaceInputJumps ++ [ [ (jump "filter_common") ] ]);

            forward =
              chainFromRules
                (add chain {
                  type = f: f.filter;
                  hook = f: f.forward;
                  prio = f: f.filter;
                  policy = policyFn cfg.forwardPolicy;
                })
                (
                  cfg.extraForwardRules
                  ++ vrfIsolationRules
                  ++ vrfForwardRules
                  ++ ifaceForwardJumps
                  ++ [ [ (jump "filter_common") ] ]
                );
          }
          // lib.optionalAttrs (cfg.extraOutputRules != [ ]) {
            output = chainFromRules (add chain {
              type = f: f.filter;
              hook = f: f.output;
              prio = f: f.filter;
              policy = f: f.accept;
            }) cfg.extraOutputRules;
          }
        );
      }
      // natTableAttrs
      // nat6TableAttrs
      // pbrTableAttrs
      // rawTableAttrs
    );

  activeRuleset = if cfg.ruleset != null then cfg.ruleset else generatedRuleset;

  rulesFile = pkgs.writeText "firewall.json" (builtins.toJSON activeRuleset);

  loadScript = pkgs.writeShellScript "nftables-load-json" ''
    ${lib.optionalString cfg.flushRuleset "${pkgs.nftables}/sbin/nft flush ruleset"}
    ${pkgs.nftables}/sbin/nft -j -f ${rulesFile}
  '';
in
{
  options.lh.firewall = {
    enable = lib.mkEnableOption "notnft JSON firewall";

    conntrack = lib.mkOption {
      type = lib.types.enum [
        "full"
        "stateless"
        "statelessForward"
        "disabled"
      ];
      default = "full";
      description = ''
        Conntrack handling inserted at the top of filter_common.
        - "full": accept established/related, drop invalid (default).
        - "stateless": accept established/related, let invalid pass through.
          Use this when asymmetric routing causes return traffic to appear invalid.
        - "statelessForward": full conntrack for router-local traffic; forwarded
          traffic is notrack'd in a raw prerouting chain (fib daddr type != local)
          so conntrack never sees it. Combines strict input conntrack with zero
          conntrack overhead on transit paths and correct handling of asymmetric
          routing for forwarded flows.
        - "disabled": no conntrack rules.
      '';
    };

    floatingRules = lib.mkOption {
      type = lib.types.listOf lib.types.unspecified;
      default = [ ];
      description = "Rules evaluated before per-interface dispatch, in both input and forward hooks.";
    };

    interfaces = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            rules = lib.mkOption {
              type = lib.types.listOf lib.types.unspecified;
              default = [ ];
              description = "Per-interface ingress rules, applied regardless of whether traffic is input or forwarded.";
            };
            inputOnlyRules = lib.mkOption {
              type = lib.types.listOf lib.types.unspecified;
              default = [ ];
              description = ''
                Per-interface rules only reachable from the input hook.
                These are placed in a separate iface_<name>_input chain that
                filter_common (shared with forward) never jumps to.
                Use for protocols that must only be accepted destined to the
                router itself, e.g. BGP (tcp/179) and BFD (udp/3784).
              '';
            };
            forwardOnlyRules = lib.mkOption {
              type = lib.types.listOf lib.types.unspecified;
              default = [ ];
              description = ''
                Per-interface rules only reachable from the forward hook.
                These are placed in a separate iface_<name>_forward chain that
                the input hook never jumps to.
                Use for forwarding-specific policy that must not affect traffic
                destined to the router itself.
              '';
            };
          };
        }
      );
      default = { };
      description = "Per-interface rule sets, keyed by interface name.";
    };

    extraInputRules = lib.mkOption {
      type = lib.types.listOf lib.types.unspecified;
      default = [ ];
      description = "Extra rules placed in the input hook chain before jumping to filter_common.";
    };

    extraForwardRules = lib.mkOption {
      type = lib.types.listOf lib.types.unspecified;
      default = [ ];
      description = "Extra rules placed in the forward hook chain before jumping to filter_common (e.g. MSS clamping).";
    };

    extraOutputRules = lib.mkOption {
      type = lib.types.listOf lib.types.unspecified;
      default = [ ];
      description = ''
        Rules placed in an inet filter output hook chain (policy: accept).
        Only generated when non-empty. Use for egress restrictions on
        specific interfaces (e.g. IXP peering ports that must only carry BGP/ICMP).
      '';
    };

    inputPolicy = lib.mkOption {
      type = lib.types.enum [
        "drop"
        "accept"
      ];
      default = "drop";
      description = "Default policy for the input hook chain.";
    };

    forwardPolicy = lib.mkOption {
      type = lib.types.enum [
        "drop"
        "accept"
      ];
      default = "drop";
      description = "Default policy for the forward hook chain.";
    };

    ruleset = lib.mkOption {
      type = lib.types.nullOr lib.types.unspecified;
      default = null;
      description = "Raw escape hatch: a dsl.ruleset value that overrides all structured options.";
    };

    flushRuleset = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Flush the existing ruleset before loading the new one.";
    };

    # ── NAT (OPNsense-style) ──────────────────────────────────────────────────
    # Ignored when `ruleset` is set (escape hatch takes full ownership).

    nat = {
      outbound = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              oifname = lib.mkOption {
                type = lib.types.str;
                description = "Egress interface (e.g. \"wan\"). OPNsense: NAT > Outbound > Interface.";
              };
              source = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Source CIDR to match, or null for any. OPNsense: NAT > Outbound > Source.";
              };
              destination = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Destination CIDR to match, or null for any. OPNsense: NAT > Outbound > Destination.";
              };
              type = lib.mkOption {
                type = lib.types.enum [
                  "masquerade"
                  "snat"
                ];
                default = "masquerade";
                description = ''
                  Translation type.
                  - masquerade: source address is replaced with the outbound interface address (dynamic).
                  - snat: source address is replaced with the static addr value.
                '';
              };
              addr = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "SNAT target address. Required when type = \"snat\".";
              };
            };
          }
        );
        default = [ ];
        description = "Outbound NAT rules (ip nat postrouting). Analogous to OPNsense Firewall > NAT > Outbound.";
      };

      portForwards = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              iifname = lib.mkOption {
                type = lib.types.str;
                description = "Ingress interface (e.g. \"wan\"). OPNsense: NAT > Port Forward > Interface.";
              };
              protocol = lib.mkOption {
                type = lib.types.enum [
                  "tcp"
                  "udp"
                  "tcp_udp"
                ];
                description = "Transport protocol. tcp_udp emits two rules, one for each.";
              };
              destination = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "External destination IP/CIDR filter, or null for any. OPNsense: NAT > Port Forward > Destination.";
              };
              dstPort = lib.mkOption {
                type = lib.types.either lib.types.port (lib.types.listOf lib.types.port);
                description = "External destination port(s). OPNsense: NAT > Port Forward > Destination port range.";
              };
              target = lib.mkOption {
                type = lib.types.str;
                description = "Redirect target IP address. OPNsense: NAT > Port Forward > Redirect target IP.";
              };
              targetPort = lib.mkOption {
                type = lib.types.nullOr lib.types.port;
                default = null;
                description = "Redirect target port. Null means same port as matched. OPNsense: NAT > Port Forward > Redirect target port.";
              };
            };
          }
        );
        default = [ ];
        description = "Port forward rules (ip nat prerouting DNAT). Analogous to OPNsense Firewall > NAT > Port Forward.";
      };

      oneToOne = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              externalAddr = lib.mkOption {
                type = lib.types.str;
                description = "External (WAN-side) IPv4 address. OPNsense: NAT > 1:1 > External subnet.";
              };
              internalAddr = lib.mkOption {
                type = lib.types.str;
                description = "Internal (LAN-side) IPv4 address. OPNsense: NAT > 1:1 > Internal IP.";
              };
              iifname = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Optional ingress interface filter for the DNAT (inbound) direction.";
              };
              oifname = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Optional egress interface filter for the SNAT (outbound) direction.";
              };
            };
          }
        );
        default = [ ];
        description = "1:1 NAT mappings (bidirectional DNAT+SNAT). Analogous to OPNsense Firewall > NAT > 1:1.";
      };

      extraPreroutingRules = lib.mkOption {
        type = lib.types.listOf lib.types.unspecified;
        default = [ ];
        description = "Extra raw notnft DSL rules appended to the ip nat prerouting chain.";
      };

      extraPostroutingRules = lib.mkOption {
        type = lib.types.listOf lib.types.unspecified;
        default = [ ];
        description = "Extra raw notnft DSL rules appended to the ip nat postrouting chain.";
      };

      extraPostroutingRulesV6 = lib.mkOption {
        type = lib.types.listOf lib.types.unspecified;
        default = [ ];
        description = "Extra raw notnft DSL rules in the ip6 nat postrouting chain.";
      };

      extraOutputRules = lib.mkOption {
        type = lib.types.listOf lib.types.unspecified;
        default = [ ];
        description = "Extra raw notnft DSL rules in the ip nat output chain (DNAT for locally-originated traffic).";
      };

      # ── VRF customer NAT (generic, connmark-based reply steering) ────────────
      # Multiple customers, each in their own VRF, NAT'd to a shared WAN address.
      # VRFs are isolated and may use overlapping/duplicate IPv4 prefixes.

      vrfWanInterface = lib.mkOption {
        type = lib.types.str;
        default = "wan";
        description = "Default egress (WAN) interface for VRF zones that do not set their own `wanInterface`.";
      };

      vrfRulePriority = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 300;
        description = "Base priority for the generated `fwmark → table` ip rules (incremented by one per zone).";
      };

      vrfZones = lib.mkOption {
        default = { };
        description = ''
          Per-customer VRF NAT zones behind a shared WAN address.

          Each zone masquerades (NAPT) its customer interface(s) out the WAN, is
          isolated from every other zone, and may use overlapping/duplicate
          IPv4 prefixes. Reply traffic is disambiguated via connmark: the flow is
          tagged with the zone mark on customer ingress, the mark is restored into
          the packet's fwmark on WAN ingress, and a generated ip rule steers it
          into the zone's VRF routing table.

          Enabling this generates: an inet `vrf_prerouting` mangle chain, masquerade
          and DNAT rules in the `ip nat` table, forward accept/isolation rules, the
          `vrf-nat-routing` systemd service (fwmark ip rules + per-VRF default
          routes), and loosens `rp_filter` to 2.
        '';
        type = lib.types.attrsOf (
          lib.types.submodule (
            { config, ... }:
            {
              options = {
                table = lib.mkOption {
                  type = lib.types.ints.unsigned;
                  description = "VRF routing table number (must match the systemd-networkd vrf netdev `Table`).";
                };
                mark = lib.mkOption {
                  type = lib.types.ints.unsigned;
                  default = config.table;
                  defaultText = lib.literalExpression "config.table";
                  description = "connmark / fwmark value for this zone. Defaults to the table number.";
                };
                ingressInterfaces = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  description = "Customer-facing interfaces enslaved to this VRF (e.g. [ \"leon\" ]).";
                };
                wanInterface = lib.mkOption {
                  type = lib.types.str;
                  default = cfg.nat.vrfWanInterface;
                  defaultText = lib.literalExpression "config.lh.firewall.nat.vrfWanInterface";
                  description = "Egress (WAN) interface for this zone.";
                };
                masquerade = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "Masquerade (NAPT) this zone's egress to the WAN interface address.";
                };
                allowV6Inbound = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = ''
                    Accept new inbound IPv6 connections from the WAN destined to this
                    zone's `prefixes.v6` (IPv6 is globally routed, not NAT'd). Inter-zone
                    traffic stays blocked regardless. Set false to drop inbound v6.
                  '';
                };
                manageV6Routes = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = ''
                    Install the link route for each `prefixes.v6` entry into the VRF
                    table (so the VRF can ND-deliver to the customer). Set false when
                    BIRD originates these routes instead (lh.router.bird.vrfs with
                    matching `staticRoutesV6` or a customer BGP session). The WAN-ingress
                    steering ip rule is installed regardless.
                  '';
                };
                prefixes = lib.mkOption {
                  default = { };
                  description = "Customer prefixes for this zone, used to generate inter-zone isolation drops and inbound v6 accepts.";
                  type = lib.types.submodule {
                    options = {
                      v4 = lib.mkOption {
                        type = lib.types.listOf lib.types.str;
                        default = [ ];
                        description = "Customer IPv4 prefixes.";
                      };
                      v6 = lib.mkOption {
                        type = lib.types.listOf lib.types.str;
                        default = [ ];
                        description = "Customer IPv6 prefixes.";
                      };
                    };
                  };
                };
                portForwards = lib.mkOption {
                  default = [ ];
                  description = "Inbound DNAT from the shared WAN address into this customer VRF.";
                  type = lib.types.listOf (
                    lib.types.submodule {
                      options = {
                        protocol = lib.mkOption {
                          type = lib.types.enum [
                            "tcp"
                            "udp"
                            "tcp_udp"
                          ];
                          description = "Transport protocol. tcp_udp emits one rule per protocol.";
                        };
                        wanPort = lib.mkOption {
                          type = lib.types.port;
                          description = "External port on the shared WAN address.";
                        };
                        target = lib.mkOption {
                          type = lib.types.str;
                          description = "Customer-internal target IP.";
                        };
                        targetPort = lib.mkOption {
                          type = lib.types.nullOr lib.types.port;
                          default = null;
                          description = "Target port. Null means the same as wanPort.";
                        };
                      };
                    }
                  );
                };
                defaultRoute = lib.mkOption {
                  default = { };
                  description = "Optional per-VRF default route(s) installed into this zone's routing table by the vrf-nat-routing service.";
                  type = lib.types.submodule {
                    options = {
                      v4 = lib.mkOption {
                        default = null;
                        description = "IPv4 default route for the VRF table.";
                        type = lib.types.nullOr (
                          lib.types.submodule {
                            options = {
                              via = lib.mkOption {
                                type = lib.types.str;
                                description = "Gateway address.";
                              };
                              dev = lib.mkOption {
                                type = lib.types.str;
                                description = "Egress device (usually the WAN interface).";
                              };
                              onLink = lib.mkOption {
                                type = lib.types.bool;
                                default = true;
                                description = "Add the `onlink` flag.";
                              };
                            };
                          }
                        );
                      };
                      v6 = lib.mkOption {
                        default = null;
                        description = "IPv6 default route for the VRF table.";
                        type = lib.types.nullOr (
                          lib.types.submodule {
                            options = {
                              via = lib.mkOption {
                                type = lib.types.str;
                                description = "Gateway address (e.g. fe80::1).";
                              };
                              dev = lib.mkOption {
                                type = lib.types.str;
                                description = "Egress device (usually the WAN interface).";
                              };
                              onLink = lib.mkOption {
                                type = lib.types.bool;
                                default = false;
                                description = "Add the `onlink` flag.";
                              };
                            };
                          }
                        );
                      };
                    };
                  };
                };
              };
            }
          )
        );
      };
    };

    # ── PBR (Policy-Based Routing) ────────────────────────────────────────────
    # Generates an ip mangle table with prerouting (forwarded) and output (local)
    # chains. Marks are applied in both so that both forwarded and router-originated
    # traffic is routed by fwmark.

    pbr = {
      marks = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              mark = lib.mkOption {
                type = lib.types.ints.unsigned;
                description = "fwmark value to set (e.g. 0x101). Must match a corresponding ip rule / ip route table.";
              };
              dstCidr = lib.mkOption {
                type = lib.types.str;
                description = "Destination CIDR that triggers this mark (IPv4).";
              };
            };
          }
        );
        default = [ ];
        description = "PBR mark rules. Each entry marks packets destined for dstCidr with the fwmark in both ip mangle prerouting and output chains.";
      };

      extraPreroutingRules = lib.mkOption {
        type = lib.types.listOf lib.types.unspecified;
        default = [ ];
        description = "Extra raw notnft DSL rules in the ip mangle prerouting chain (forwarded traffic). Use the nftablesHelpers.pbrMark helper or raw DSL.";
      };

      extraOutputRules = lib.mkOption {
        type = lib.types.listOf lib.types.unspecified;
        default = [ ];
        description = "Extra raw notnft DSL rules in the ip mangle output chain (locally-originated traffic).";
      };
    };
  };

  config = lib.mkMerge [
    {
      # Always expose helpers and constants so host modules can use them without
      # importing paths manually.
      _module.args.nftablesHelpers = import ../../nftables/helpers {
        inherit (config) notnft;
      };
      _module.args.nftablesConstants = import ../../nftables/constants.nix;
    }

    (lib.mkIf cfg.enable {
      networking.firewall.enable = false;

      # Enable nftables for kernel module loading and service scaffolding.
      # ExecStart/ExecReload are overridden below to use JSON mode (-j).
      networking.nftables.enable = true;
      networking.nftables.flushRuleset = false;

      systemd.services.nftables.serviceConfig = {
        ExecStart = lib.mkForce "${loadScript}";
        ExecReload = lib.mkForce "${loadScript}";
      };
    })

    (lib.mkIf (cfg.enable && hasVrfZones) {
      # NAT reply steering into VRFs is asymmetric by design (reply enters on WAN
      # in the default VRF, leaves on the customer iface): loosen rp_filter.
      boot.kernel.sysctl = {
        "net.ipv4.conf.all.rp_filter" = lib.mkForce 2;
        "net.ipv4.conf.default.rp_filter" = lib.mkForce 2;
      };

      # fwmark → VRF table ip rules and per-VRF default routes.
      systemd.services.vrf-nat-routing = {
        description = "VRF customer NAT: fwmark ip rules + per-VRF default routes";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.iproute2 ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = vrfRoutingScript;
      };
    })
  ];
}
