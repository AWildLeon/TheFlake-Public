# NFT Firewall Framework

The `lh.firewall` NixOS module is a structured notnft-based firewall framework for router hosts. It generates a single `inet firewall` table with a fixed chain topology, and exposes per-interface rule injection points so individual host configs remain small and readable.

Upstream DSL reference: [docs/notnft.md](notnft.md)

Debugging/simulation tool: [docs/packet-court.md](packet-court.md)

## Files

| Path                              | Role                                                          |
| --------------------------------- | ------------------------------------------------------------- |
| `modules/networking/firewall.nix` | NixOS module — options and ruleset generator                  |
| `nftables/helpers/default.nix`    | DSL helper functions (returns rule lists)                     |
| `nftables/constants.nix`          | Shared network constants (CIDRs, service IPs, ICMP lists)     |
| `nftables/flake-part.nix`         | flake-parts module — packages all configs as `nftables-rules` |

## Chain topology

```
input hook (policy: inputPolicy)
  └─ extraInputRules
  └─ iface_<name>_input  (for each interface with inputOnlyRules)
  └─ filter_common
       ├─ conntrack rule
       ├─ lo accept
       ├─ floating chain  (if floatingRules != [])
       └─ iface_<name>    (for each interface with rules)

forward hook (policy: forwardPolicy)
  └─ extraForwardRules
  └─ iface_<name>_forward  (for each interface with forwardOnlyRules)
  └─ filter_common
       └─ (same as above)
```

`filter_common` is shared between both hooks. Any rule placed there fires for traffic destined to the router **and** traffic being forwarded through it. Use `inputOnlyRules`/`forwardOnlyRules` to restrict a rule to one hook only.

## Options (`lh.firewall`)

### `enable`

Type: `bool`  
Disables `networking.firewall`, enables `networking.nftables`, and installs a systemd override that loads the generated JSON ruleset via `nft -j -f`.

### `conntrack`

Type: `enum [ "full" "stateless" "disabled" ]`  
Default: `"full"`

Inserts a conntrack rule at the top of `filter_common`.

| Value                | Behaviour                                                                                                                                                                                            |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `"full"`             | accept established/related, **drop** invalid                                                                                                                                                         |
| `"stateless"`        | accept established/related, let invalid pass through — use when asymmetric routing makes return traffic appear invalid                                                                               |
| `"statelessForward"` | full conntrack for router-local traffic; forwarded traffic is notrack'd via `fib daddr type != local` in a raw prerouting chain so conntrack never sees it — best of both worlds for transit routers |
| `"disabled"`         | no conntrack rule inserted                                                                                                                                                                           |

### `floatingRules`

Type: `list of rules`  
Default: `[]`

Rules evaluated in both hooks before per-interface dispatch. When non-empty, a `floating` chain is generated and jumped to from `filter_common`. Use for rules that apply to all interfaces — typically ICMP and BGP.

### `interfaces.<name>.rules`

Rules placed in `iface_<name>` — reachable from both input and forward. Use for source-based ACLs that apply regardless of whether the traffic terminates on the router or is forwarded.

### `interfaces.<name>.inputOnlyRules`

Rules placed in `iface_<name>_input` — only reachable from the input hook. Use for protocols that must only be accepted when destined to the router itself (BGP port 179, BFD port 3784, DHCP relay port 67).

### `interfaces.<name>.forwardOnlyRules`

Rules placed in `iface_<name>_forward` — only reachable from the forward hook. Use for forwarding policy that must not affect traffic to the router itself.

### `extraInputRules`

Rules prepended to the input chain, before `filter_common`. Runs for all interfaces. Use for router-wide input-only policy (e.g. accepting BGP from any interface).

### `extraForwardRules`

Rules prepended to the forward chain, before `filter_common`. Use for MSS clamping and other forwarding-wide rules that must run before per-interface dispatch.

### `extraOutputRules`

Rules placed in an `inet filter` output hook chain (policy: accept). The chain is only generated when this list is non-empty. Use for egress restrictions on specific interfaces — for example, an IXP peering port that must only carry BGP, ICMP, and established traffic:

```nix
extraOutputRules = [
  [(is.eq meta.oifname "locix_dus") (vmap ct.state { established = accept; related = accept; }) ]
  [(is.eq meta.oifname "locix_dus") (is.eq tcp.dport 179) accept]
  [(is.eq meta.oifname "locix_dus") (is.eq ip.protocol (f: f.icmp)) accept]
  [(is.eq meta.oifname "locix_dus") (is.eq ip6.nexthdr (f: f.ipv6-icmp)) accept]
  [(is.eq meta.oifname "locix_dus") drop]
];
```

### `inputPolicy` / `forwardPolicy`

Type: `enum [ "drop" "accept" ]`  
Default: `"drop"` for both

Default policy of the respective hook chain.

### `ruleset`

Type: `null | dsl.ruleset value`  
Default: `null`

Raw escape hatch. When set, the entire generated ruleset is replaced by this value. Useful for hosts that need tables outside the `inet firewall` structure (NAT, mangle, netdev) alongside the standard filter, or that haven't been migrated to the framework yet.

### `flushRuleset`

Type: `bool`  
Default: `true`

Runs `nft flush ruleset` before loading the new rules.

## Module arguments

When `modules/networking/firewall.nix` is imported, two module arguments are injected unconditionally (even if `lh.firewall.enable = false`):

| Argument            | Source                         | Contents                    |
| ------------------- | ------------------------------ | --------------------------- |
| `nftablesHelpers`   | `nftables/helpers/default.nix` | DSL helper functions        |
| `nftablesConstants` | `nftables/constants.nix`       | Plain Nix network constants |

Both are available in any host module file as regular function arguments:

```nix
{ nftablesHelpers, nftablesConstants, config, ... }:
with config.notnft.dsl; with payload;
{ ... }
```

## nftablesHelpers reference

All helpers return a **list of rules** (`[[stmt...] [stmt...] ...]`). Concatenate with `++` to compose.

### Conntrack and loopback

| Helper      | Effect                                   |
| ----------- | ---------------------------------------- |
| `conntrack` | accept established/related, drop invalid |
| `acceptLo`  | accept all loopback traffic              |

### ICMP

| Helper              | Signature             | Effect                                                                                               |
| ------------------- | --------------------- | ---------------------------------------------------------------------------------------------------- |
| `acceptIcmp`        | —                     | accept all ICMP and ICMPv6                                                                           |
| `acceptIcmpTypes`   | `v4types: v6types: …` | accept only the listed type strings                                                                  |
| `acceptIcmpDefault` | —                     | sane diagnostic subset (echo-request, unreachable, TTL exceeded, parameter-problem; plus NDP for v6) |
| `icmpRateLimit`     | `rate: …`             | rate-limited ICMP accept then blanket ICMP drop; for WAN ingress                                     |

### BGP / BFD

| Helper         | Signature           | Effect                                                         |
| -------------- | ------------------- | -------------------------------------------------------------- |
| `bgpPeers`     | `peers4: peers6: …` | accept BGP (tcp/179) and BFD (udp/3784) from explicit IP lists |
| `bgpIfaces`    | `ifaces: …`         | accept BGP + BFD arriving on the listed interfaces             |
| `bgpLinkLocal` | —                   | accept BGP from link-local IPv6 (fe80::/10)                    |

### WireGuard

| Helper     | Signature  | Effect                                      |
| ---------- | ---------- | ------------------------------------------- |
| `acceptWg` | `ports: …` | accept UDP on the given WireGuard port list |

### TCP / UDP ports

| Helper         | Signature  | Effect                                                  |
| -------------- | ---------- | ------------------------------------------------------- |
| `acceptTcp`    | `ports: …` | accept TCP on the given ports                           |
| `acceptUdp`    | `ports: …` | accept UDP on the given ports                           |
| `acceptTcpUdp` | `ports: …` | accept TCP and UDP on the same ports (dual-stack aware) |

### Network sets

| Helper               | Signature       | Effect                                                                          |
| -------------------- | --------------- | ------------------------------------------------------------------------------- |
| `acceptFromNetworks` | `{ v4, v6 }: …` | accept all traffic sourced from a `{ v4 = [cidr...]; v6 = [cidr...]; }` attrset |

Designed to pair with `nftablesConstants.privilegedNetworks`.

### NAT

| Helper         | Signature     | Effect                                                 |
| -------------- | ------------- | ------------------------------------------------------ |
| `masqLanToWan` | `lan: wan: …` | masquerade traffic leaving `wan` that arrived on `lan` |

### MSS clamping

```nix
mssClamp { iface = "ppp0"; mtu = 1492; }
# or with explicit values:
mssClamp { iface = "wg*"; mss4 = 1392; mss6 = 1372; }
```

Emits two rules (IPv4 + IPv6 SYN) that clamp TCP MSS for egress on the given interface pattern. Place in `extraForwardRules`.

- `mtu` is the interface MTU; `mss4`/`mss6` are derived as `mtu - 40` / `mtu - 60`.
- `mss4` defaults to 1452 and `mss6` to `mss4 - 20` when neither `mtu` nor explicit values are given.

## nftablesConstants reference

Plain Nix values — no DSL dependency. Usable in firewall rules, BIRD configs, ACLs, etc.

| Constant              | Type         | Contents                                                                    |
| --------------------- | ------------ | --------------------------------------------------------------------------- |
| `privilegedNetworks`  | `{ v4, v6 }` | Admin, infra, VPN road-warrior, and VPN-GW subnets — full management access |
| `AS213579Prefixes`    | `{ v4, v6 }` | Publicly announced IP space for AS213579                                    |
| `homeRouteReflectors` | `{ v6 }`     | iBGP route reflector addresses for the home site                            |
| `icmpTypes.v4`        | `[string]`   | Diagnostically necessary ICMPv4 types                                       |
| `icmpTypes.v6`        | `[string]`   | Diagnostically necessary ICMPv6 types (includes NDP for hosts)              |
| `icmpTypes.v6Router`  | `[string]`   | ICMPv6 types extended for routers running radvd (adds RS + RA)              |
| `services.home.dns`   | `{ v4, v6 }` | Recursive DNS resolver addresses                                            |
| `services.home.ntp`   | `{ v4, v6 }` | NTP server (ChronoLease) addresses                                          |
| `services.home.dhcp`  | `{ v4, v6 }` | DHCP server (ChronoLease) addresses                                         |

## Minimal example

```nix
{ nftablesHelpers, nftablesConstants, config, ... }:
with config.notnft.dsl; with payload;
{
  lh.firewall = {
    enable = true;

    floatingRules =
      nftablesHelpers.acceptIcmpTypes
        nftablesConstants.icmpTypes.v4
        nftablesConstants.icmpTypes.v6Router;

    interfaces.backbone = {
      rules = nftablesHelpers.acceptFromNetworks nftablesConstants.privilegedNetworks;
      inputOnlyRules =
        nftablesHelpers.bgpPeers [] nftablesConstants.homeRouteReflectors.v6;
    };

    extraInputRules = [
      [(is.eq tcp.dport 22) accept]
    ];
  };
}
```

## Full-featured example

```nix
{ nftablesHelpers, nftablesConstants, config, ... }:
with config.notnft.dsl; with payload;
{
  lh.firewall = {
    enable = true;
    conntrack = "full";

    floatingRules =
      nftablesHelpers.acceptIcmpTypes
        nftablesConstants.icmpTypes.v4
        nftablesConstants.icmpTypes.v6Router;

    interfaces.backbone = {
      rules = nftablesHelpers.acceptFromNetworks nftablesConstants.privilegedNetworks;
      inputOnlyRules =
        nftablesHelpers.bgpPeers
          []
          nftablesConstants.homeRouteReflectors.v6;
      forwardOnlyRules = [
        [(is.eq ip6.saddr (cidr "2a14:47c0:e047::4/128"))
         (is.eq ip6.daddr (cidr "2a14:47c0:e002:3::99/128"))
         (is.eq tcp.dport 8123) accept]
      ];
    };

    interfaces.wan = {
      rules = nftablesHelpers.icmpRateLimit 20;
    };

    extraInputRules = [
      [(is.eq udp.dport 67) accept]   # DHCP relay
    ];

    extraForwardRules =
      nftablesHelpers.mssClamp { iface = "ppp0"; mtu = 1492; }
      ++ nftablesHelpers.mssClamp { iface = "wg*"; mss4 = 1392; mss6 = 1372; };
  };
}
```

## Adding a rule that only applies when forwarded, not when destined to the router

Put it in `interfaces.<name>.forwardOnlyRules`. The framework generates a separate `iface_<name>_forward` chain that only the forward hook jumps to — the input hook never sees it.

## VRF customer NAT with overlapping prefixes (`nat.vrfZones`)

For routers that host several customers, each in their own VRF, that must reach
the IPv4 internet via NAT behind a **single shared WAN address**, stay fully
isolated from each other, and may use **overlapping/duplicate prefixes**.

The hard part is the NAT reply path: with one shared WAN IP, all customers are
NAPT'd behind it (the per-flow source port keeps conntrack unique), but after a
reply is un-NAT'd its destination (e.g. `10.0.0.5`) no longer identifies which
VRF it belongs to. `nat.vrfZones` disambiguates by **connmark** instead of
destination IP:

```
ingress(customer iface) → ct mark set <mark>           # tag the flow
ingress(wan)            → meta mark set ct mark         # restore on replies + inbound DNAT
ip rule fwmark <mark>   → VRF table                     # steer back into the right VRF
```

### What it generates

| Artifact                            | Purpose                                                              |
| ----------------------------------- | -------------------------------------------------------------------- |
| inet `vrf_prerouting` (mangle prio) | connmark tagging + fwmark restore                                    |
| `ip nat` postrouting                | `oifname <wan> ct mark <mark> masquerade` per zone                   |
| `ip nat` prerouting                 | DNAT for each zone's `portForwards`                                  |
| forward chain rules                 | customer→WAN accept, inbound port-forward accept, inter-zone drops   |
| `vrf-nat-routing` systemd service   | `ip rule fwmark → table`, per-VRF default routes, v6 inbound routing |
| `rp_filter = 2`                     | asymmetric reply steering is intentional                             |

> **VRF + netfilter caveat:** in the `forward` hook the ingress interface is the
> VRF _master_ device (e.g. `vrf_<name>`), not the physical customer interface
> (e.g. `<name>`). The generated forward rules therefore match customer→WAN on
> **egress + connmark** (the mark is set on physical ingress in `vrf_prerouting`,
> before the VRF swap), and inbound on the WAN interface (which is never
> VRF-enslaved). Don't add manual `iifname "<customer-iface>"` accepts to the
> forward chain — they will never match.

### Required networkd setup (host)

The VRF netdevs, the table numbers, and the customer-interface enslavement live
in the host's `network.nix` (systemd-networkd) — `nat.vrfZones` only references
them. The shared WAN stays in the **default** VRF.

### IPv6

IPv6 is **routed, not NAT'd** (globally unique, no overlap). For each zone with
`prefixes.v6`, the service installs a link route in the VRF table plus an
`iif <wan> to <prefix> lookup <vrfTable>` ip rule, so return/inbound traffic
arriving on the WAN is steered into the customer's VRF. A bird-style
`route <prefix> via <iface>` in the main table does **not** work here, because the
customer interface is VRF-enslaved and the kernel rejects such a route. Customer
egress uses the VRF's `defaultRoute.v6`; inbound is gated by `allowV6Inbound`.

### Options per zone

| Option                 | Meaning                                                                                             |
| ---------------------- | --------------------------------------------------------------------------------------------------- |
| `table`                | VRF routing table number (must match the vrf netdev `Table`)                                        |
| `mark`                 | connmark/fwmark value — defaults to `table`                                                         |
| `ingressInterfaces`    | customer-facing interfaces enslaved to this VRF                                                     |
| `wanInterface`         | egress interface — defaults to `nat.vrfWanInterface` (`"wan"`)                                      |
| `masquerade`           | NAPT this zone to the WAN address (default `true`)                                                  |
| `prefixes.{v4,v6}`     | customer prefixes — drive inter-zone isolation drops and inbound v6 accepts                         |
| `allowV6Inbound`       | accept new inbound v6 to this zone's prefixes (v6 is routed, not NAT'd)                             |
| `manageV6Routes`       | install the v6 prefix link route into the VRF table (default `true`); set `false` when BIRD owns it |
| `portForwards`         | inbound DNAT `{ protocol; wanPort; target; targetPort; }`                                           |
| `defaultRoute.{v4,v6}` | optional `{ via; dev; onLink; }` default route injected into the VRF table                          |

### Example

```nix
lh.firewall.nat.vrfZones = {
  leon = {
    table = 300;
    ingressInterfaces = [ "leon" ];
    prefixes = { v4 = [ "10.1.0.0/29" ]; v6 = [ "2a01:4f8:172:14ac::200/120" ]; };
    defaultRoute = {
      v4 = { via = "10.21.254.255"; dev = "wan"; onLink = true; };
      v6 = { via = "fe80::1"; dev = "wan"; };
    };
    portForwards = [
      { protocol = "tcp"; wanPort = 2201; target = "10.1.0.2"; targetPort = 22; }
    ];
  };
};
```

Adding a customer = one VRF netdev + interface in `network.nix`, plus one
`vrfZones` entry. Overlapping prefixes between zones need no special handling.

### BIRD integration (VRF-aware routing)

The NAT framework owns the **policy** layer: ip rules (fwmark/iif steering), NAT,
and the egress `defaultRoute`. The **routes inside** a VRF table (customer
prefixes, BGP-learned) can be owned by BIRD instead via `lh.router.bird.vrfs`,
which generates a `vrf_<name>4/6` table pair and VRF-bound `direct` + `kernel`
protocols (`vrf "<iface>"` + `kernel table <N>`). This is the path for customers
that speak BGP — bind the session with `vrf "<iface>"` and
`ipv6 { table vrf_<name>6; ... }`.

To avoid two owners of the same kernel route, set `manageV6Routes = false` on the
NAT zone when BIRD originates the prefix (the NAT framework then installs only the
steering ip rule, not the link route). Use the same `table` number in both. BIRD's
VRF kernel protocol uses `import none`, so it never scrubs the NAT-installed
default route or the connected routes. Existing non-VRF BIRD hosts are unaffected
(`vrfs` defaults to `{}`).

## When the framework is not enough

Set `lh.firewall.ruleset` to a `dsl.ruleset` value to bypass all generated chains entirely. This is appropriate when a host needs tables outside `inet firewall` (e.g. `netdev` ingress filtering, `ip nat`, policy-based routing marks) that cannot be expressed via the structured options alone.

Hosts that use raw `networking.nftables.ruleset` (plain text, not the DSL) instead of `lh.firewall` are pre-framework and have not yet been migrated.
