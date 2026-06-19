# Packet court (`lhflake packet`)

`lhflake packet` is a practical firewall simulator for this flake's `lh.firewall`
framework. It evaluates a selected host, exports `config.lh.firewall.analysis` /
`config.lh.firewall.analysisJson`, and simulates a hypothetical packet against the
generated notnft/nftables JSON.

It is intentionally **not** a complete nftables interpreter. If a potentially
matching rule uses an expression the simulator cannot model, the verdict is
`UNKNOWN` and the output explains why.

## Examples

```bash
# Forwarded packet from a customer VRF to WAN.
lhflake packet router.hetzner.pve1-fsn1-router \
  --path forward --from vrf_leon --to wan --dst 1.1.1.1 --proto tcp --dport 443

# Inbound port-forward after DNAT (WAN :2201 -> 10.1.0.2:22 on that host).
lhflake packet router.hetzner.pve1-fsn1-router \
  --path forward --from wan --to vrf_leon --dst 138.201.59.182 \
  --proto tcp --dport 2201

# Router-local input path.
lhflake packet router.hetzner.pve1-fsn1-router \
  --path input --from vrf_leon --proto tcp --dport 179

# Discovery / debugging.
lhflake packet router.hetzner.pve1-fsn1-router --list-interfaces
lhflake packet router.hetzner.pve1-fsn1-router --list-zones
lhflake packet router.hetzner.pve1-fsn1-router --dump-model | jq .
lhflake packet router.hetzner.pve1-fsn1-router --json \
  --path forward --from deads --to wan --proto udp --dport 53
```

## Model boundary

The NixOS firewall module exposes:

```nix
config.lh.firewall.analysis
config.lh.firewall.analysisJson
```

The first is the native evaluated Nix attrset; the second is the JSON boundary used by the CLI. The export contains:

- generated nftables JSON for the active `lh.firewall` ruleset;
- input/forward policy;
- configured interface names and rule counts;
- structured NAT/PBR metadata where it exists (`nat.outbound`, `portForwards`,
  `oneToOne`, `vrfZones`, `pbr.marks`);
- booleans warning about raw escape hatches.

No secrets are included.

The simulator primarily walks the generated `inet firewall` chains, because that
is the real evaluated output while still preserving the framework's topology:

- `input` hook;
- `forward` hook;
- `filter_common`;
- `floating`;
- per-interface `iface_<name>`, `iface_<name>_input`, and
  `iface_<name>_forward` chains.

It also models first-match IPv4 `ip nat` `prerouting`/`postrouting` translation
well enough to explain DNAT/SNAT/masquerade and to update destination address/port
for subsequent filter simulation.

## Currently modeled

- forward and input filter paths;
- chain policy (`accept`/`drop`);
- `accept`, `drop`, `reject`, `return`, `jump`, `goto`;
- equality matches on:
  - `meta.iifname`, `meta.oifname`;
  - `ip/ip6 saddr`, `ip/ip6 daddr` including prefix sets;
  - `ip protocol`, `ip6 nexthdr`;
  - `tcp/udp/th sport` and `dport`;
  - `ct.state`, `ct.mark`, and packet `meta mark` (`--mark`);
- `ct.state vmap { established : accept, related : accept, invalid : drop }`;
- TCP flag membership for common MSS-clamp rules (`--tcp-flags syn`);
- simple wildcard interface strings (`wg*`);
- IPv4 DNAT/SNAT/masquerade reporting, including the flake's NETMAP-style address expression;
- basic `lh.firewall.nat.vrfZones` convenience inference of `ct.mark` for
  customer-interface/VRF -> WAN packets.

## Limitations / fail-closed behavior

The simulator returns `UNKNOWN` when a potentially matching rule depends on an
unsupported matcher/expression. Known partial or unsupported areas include:

- rate limits (`limit`);
- arbitrary `fib`, bitwise expressions outside the known NETMAP shape, and sets/maps beyond simple equality;
- exact conntrack side effects beyond the explicitly supplied `--ct-state` and
  inferred/supplied `--ct-mark`;
- VRF routing decisions and policy routing (`ip rule`) beyond rule matching;
- netdev/raw hooks and notrack side effects;
- most mangling actions (MSS clamp is explained but not behaviorally relevant; meta/ct marks are modeled when simple);
- IPv6 NAT extras;
- source-file attribution: notnft JSON currently does not preserve Nix source
  locations, so matched rules are shown as generated JSON expressions.

When unsure, packet court should prefer:

```text
Verdict: UNKNOWN
Reason: unsupported expression ...
```

rather than overclaiming that the real router would accept or drop the packet.
