# notnft

A pure-Nix DSL that compiles to nftables JSON. It type-checks the structure of your firewall rules at evaluation time using nixpkgs's module/option system.

Upstream: https://github.com/chayleaf/notnft

## Integration in this flake

notnft is a flake input (`inputs.notnft`). Its NixOS module is not yet wired up globally — when you want to use it in a host, import `inputs.notnft.nixosModules.default` in that host's module list.

Once imported, the evaluated library is available as either:

- the module argument `notnft` (preferred in module files), or
- `config.notnft` (in any NixOS module after import).

```nix
# in a NixOS module
{ notnft, ... }:
with notnft.dsl; with payload;
{
  # ...
}
```

## Core idea

You write rules using the `dsl` attribute. The DSL produces an intermediate representation; nftables JSON is obtained by calling `builtins.toJSON` on the result of `dsl.ruleset { ... }`.

The result is meant to be fed to `nft -j -f` or used with `networking.nftables.jsonRules` (if available), or with [nixos-router](https://github.com/chayleaf/nixos-router).

## Accessing the DSL

```nix
{ notnft, ... }:
let
  inherit (notnft) dsl;
  inherit (dsl) payload;
in
# or equivalently:
with notnft.dsl; with payload;
```

`payload` is a nested attrset of `{ <protocol> = { <field> = <expr>; }; }`. Doing `with payload;` lets you write `tcp.dport` instead of `payload.tcp.dport`.

## Enums

Nftables has many string constants (families, hooks, chain types, TCP flags, protocols, …). notnft calls these _enums_.

**Three ways to use them:**

1. **String literals** — `"inet"`, `"syn"`, `"accept"`. Simple but no typo checking.

2. **Enum objects** — `notnft.families.inet`, `notnft.tcpFlags.syn`. Verbose.

3. **Lambda syntax** (recommended) — anywhere an enum is expected, pass a function:

   ```nix
   { type = f: f.filter; hook = f: f.ingress; policy = f: f.accept; }
   ```

   The DSL calls the function with the correct enum attrset and resolves the value. Typos become evaluation errors.

4. **`oneEnum` / "One Enum to Rule Them All"** — `with dsl.oneEnumToRuleThemAll;` puts all enum values in scope. Convenient but pollutes the namespace and gives worse error messages on typos. Use it when you know what you're doing.

   ```nix
   with dsl.oneEnum;
   bit.or payload.tcp.flags fin syn rst psh ack urg
   ```

## Ruleset structure

```nix
builtins.toJSON (dsl.ruleset {
  <table_name> = add table { family = f: f.<family>; } {
    <chain_name> = add chain { type = ...; hook = ...; prio = ...; policy = ...; }
      [<stmt> <stmt> ...]   # rule 1
      [<stmt> <stmt> ...];  # rule 2

    <set_name> = add set { type = f: f.ipv4_addr; flags = f: with f; [ interval ]; }
      [ (cidr "10.0.0.0/8") ];
  };
})
```

### Commands

| DSL       | Meaning                         |
| --------- | ------------------------------- |
| `add`     | Add object if it doesn't exist  |
| `create`  | Add, error if it already exists |
| `insert`  | Prepend rules to a chain        |
| `delete`  | Delete object, error if missing |
| `destroy` | Delete object if it exists      |
| `flush`   | Clear object's contents         |

### `table`

```nix
add table { family = f: f.inet; }     # family is required
add table { family = f: f.netdev; }
add table.inet { ... }                # shorthand
```

Pass an attrset as the second argument; each key becomes the contained object's name.

Use `add existing table { family = ...; name = "..."; } { ... }` to add to a table without re-creating it.

### `chain`

```nix
add chain { type = f: f.filter; hook = f: f.input; prio = f: f.filter; policy = f: f.drop; }
  [stmt1 stmt2]   # rule 1
  [stmt3];        # rule 2
```

- `type`: `filter`, `nat`, `route`
- `hook`: `prerouting`, `input`, `forward`, `output`, `postrouting`, `ingress`, `egress`
- `prio`: integer or named priority (`filter`, `raw`, `mangle`, `security`, `srcnat`, `dstnat`, etc.)
- `policy`: `accept` or `drop`
- `dev`: required for `netdev` family chains

Chains without `type`/`hook` are regular chains (no hook, used via `jump`/`goto`).

Rules are lists of statements. You can pass them one list at a time or as a list of lists:

```nix
add chain [rule1_stmt1 rule1_stmt2] [rule2_stmt1]
# or
add chain [[rule1_stmt1 rule1_stmt2] [rule2_stmt1]]
```

### `set` / `map`

```nix
add set { type = f: f.ipv4_addr; flags = f: with f; [ interval ]; }
  [ (cidr "192.168.0.0/16") ]   # optional initial elements

add map { type = f: f.ipv4_addr; map = f: f.verdict; }
  [ [ "192.168.1.1" accept ] ]  # list of [key value] pairs
```

Reference a named set in a rule with `"@set_name"`.

## Statements

Statements are the building blocks of rules (lists inside chains).

### Verdicts

```nix
accept
drop
continue
return
jump "chain_name"
goto "chain_name"
```

### Match / comparison

```nix
is.eq  left right   # left == right
is.ne  left right   # left != right
is.gt  left right   # left >  right
is.lt  left right   # left <  right
is.ge  left right   # left >= right
is.le  left right   # left <= right
is     left right   # implicit operator (like bare "tcp flags syn" in nftables)
```

`is` is the most common — it automatically picks the operator based on context (flags check, set membership, etc.).

The `right` side (and sometimes `left`) can be a lambda to resolve enums. If `left` is an expression with known enum context (e.g. `tcp.flags`), the right-hand lambda receives the appropriate enum:

```nix
(is.eq ip.protocol (f: f.icmp))
(is tcp.flags (f: f.syn))
(is.eq ct.state (f: f.established))
```

### NAT

```nix
masquerade                        # SNAT to outgoing interface IP
masquerade { flags = ...; }
snat "1.2.3.4"
snat "1.2.3.4" 8080
snat "1.2.3.4" { flags = ...; }
dnat "10.0.0.1"
dnat "10.0.0.1" 80
redirect                          # DNAT to local host
redirect 8080
```

In `inet` tables use `snat.ip`/`snat.ip6` or pass `family` in attrs.

### Other statements

```nix
mangle meta.mark ct.mark          # set meta mark to ct mark value
mangle ct.mark meta.mark
counter                           # anonymous packet/byte counter
counter { packets = 0; bytes = 0; }
log "prefix: "                    # log with prefix
log { prefix = ".."; level = f: f.warn; }
notrack                           # disable conntrack
limit { rate = 20; per = f: f.second; }
quota { bytes = 1000000; }
fwd { dev = "eth0"; }
dup { dev = "eth0"; }
vmap <expr> { key1 = verdict1; key2 = verdict2; }   # verdict map
set.add    "@set_name" elem
set.update "@set_name" elem
set.delete "@set_name" elem
flow.add "flowtable_name"         # offload to flowtable
tproxy { ... }
reject
reject { type = f: f.tcp-reset; }
```

## Expressions

### Payload (packet headers)

```nix
# with payload; brings all protocols into scope
tcp.flags       # tcp flags field
tcp.dport       # tcp destination port
ip.saddr        # IPv4 source address
ip.daddr        # IPv4 destination address
ip6.saddr       # IPv6 source address
ip6.nexthdr     # IPv6 next header
ip.protocol     # IPv4 protocol field
icmp.type
icmpv6.type
th.dport        # transport-layer destination port (protocol-agnostic)
th.sport
udp.dport
eth.saddr
arp.saddr_ip    # ARP sender IP
# etc. — see notnft.payloadProtocols for all protocols and fields
```

### Meta / conntrack / routing

```nix
meta.iifname    # incoming interface name
meta.oifname    # outgoing interface name
meta.mark       # packet mark
meta.protocol   # ethertype / layer3 protocol
meta.l4proto

ct.state        # conntrack state
ct.mark         # conntrack mark
ct.original.saddr
ct.reply.daddr
# ct.<dir>.<key> for directional keys

rt.nexthop      # routing nexthop
rt.ip.nexthop
```

### Prefix / range / anonymous sets

```nix
cidr "10.0.0.0/8"            # prefix expression
cidr "10.0.0.1" 24           # or split form
range 1024 65535              # port range
set [ "tcp" "udp" ]           # anonymous set: { tcp, udp }
set [ [ "key1" accept ] [ "key2" drop ] ]  # anonymous map
```

### Bitwise operations

```nix
bit.and tcp.flags (f: f.syn)          # tcp flags & syn
bit.or  (f: f.fin) (f: f.syn)
bit.xor a b
bit.lsh a 2
bit.rsh a 2
# aliases: bit.or = bit."|", bit.and = bit."&", etc.
```

### Other expressions

```nix
concat tcp.dport ip.daddr           # value concatenation (a . b)
concat [ tcp.dport ip.daddr ]       # same
fib (f: with f; [ saddr iif ]) (f: f.oif)   # FIB lookup
fib (f: with f; [ daddr iif ]) (f: f.type)
numgen.inc { mod = 2; }             # round-robin modulo 2
numgen.random { mod = 4; }
jhash tcp.dport 4                   # Jenkins hash
symhash 4                           # symmetric hash
socket.mark                         # socket mark
socket.transparent
osf.name                            # OS fingerprint
ct.state                            # conntrack state expression
"@set_name"                         # named set reference
"*"                                 # wildcard
exists                              # boolean true (for set membership)
missing                             # boolean false
```

### TCP options / IPv6 extension headers

```nix
tcpOpt.maxseg.size                  # TCP MSS option size field
tcpOpt.maxseg                       # TCP MSS option presence
ipOpt.ra.value                      # IP router-alert option
exthdr.hopopts                      # IPv6 hop-by-hop header presence
exthdr.hopopts.nexthdr              # hop-by-hop next header field
sctpChunk.data.type
```

### vmap (verdict map)

```nix
vmap ct.state {
  established = accept;
  related     = accept;
  invalid     = drop;
}

vmap meta.iifname {
  lo    = accept;
  wan0  = jump "inbound_wan";
  lan0  = jump "inbound_lan";
}
```

## Important: `dsl.compile`

The DSL attaches metadata to objects for internal bookkeeping. You **must** strip this before passing to the module system or `builtins.toJSON`:

- Statements/expressions **inside** a `ruleset { }` block are cleaned up automatically.
- Any expression, statement, or command you extract **outside** a `ruleset` must be passed through `dsl.compile`:

```nix
# WRONG — raw DSL object, has __expr__ / __cmd__ etc.
let myExpr = is.eq tcp.dport 443; in ...

# CORRECT
let myExpr = dsl.compile (is.eq tcp.dport 443); in ...
```

## Full example

Router firewall (dual-stack, WAN ingress filtering, NAT, conntrack):

```nix
{ notnft, ... }:
with notnft.dsl; with payload;
{
  networking.nftables.enable = true;
  # Pass the JSON ruleset to your firewall mechanism here
  # e.g. networking.nftables.jsonRules or nixos-router
  _module.args.firewallRules = builtins.toJSON (ruleset {
    filter = add table.netdev {
      ingress_common = add chain
        [(is.eq (bit.and tcp.flags (f: bit.or f.fin f.syn)) (f: bit.or f.fin f.syn)) drop]
        [(is.eq (bit.and tcp.flags (f: bit.or f.syn f.rst)) (f: bit.or f.syn f.rst)) drop]
        [(is.eq (bit.and tcp.flags (f: with f; bit.or fin syn rst psh ack urg)) 0) drop]
        [(is tcp.flags (f: f.syn)) (is.eq tcpOpt.maxseg.size (range 0 500)) drop]
        [(is.eq ip.saddr "127.0.0.1") drop]
        [(is.eq ip6.saddr "::1") drop]
        [(is.eq (fib (f: with f; [ saddr iif ]) (f: f.oif)) missing) drop]
        [return];

      ingress_wan = add chain
        { type = f: f.filter; hook = f: f.ingress; dev = "wan0"; prio = -500; policy = f: f.drop; }
        [(jump "ingress_common")]
        [(is.ne (fib (f: with f; [ daddr iif ]) (f: f.type))
                (f: with f; set [ local broadcast multicast ])) drop]
        [(is.eq ip.protocol (f: f.icmp)) (limit { rate = 20; per = f: f.second; }) accept]
        [(is.eq ip6.nexthdr (f: f.ipv6-icmp)) (limit { rate = 20; per = f: f.second; }) accept]
        [(is.eq ip.protocol (f: f.icmp)) drop]
        [(is.eq ip6.nexthdr (f: f.ipv6-icmp)) drop]
        [(is.eq ip.protocol (f: with f; set [ tcp udp ])) (is.eq th.dport (set [ 22 80 443 ])) accept]
        [(is.eq ip6.nexthdr (f: with f; set [ tcp udp ])) (is.eq th.dport (set [ 22 80 443 ])) accept];
    };

    global = add table { family = f: f.inet; } {
      inbound = add chain
        { type = f: f.filter; hook = f: f.input; prio = f: f.filter; policy = f: f.drop; }
        [(vmap ct.state { established = accept; related = accept; invalid = drop; })]
        [(is.eq (bit.and tcp.flags (f: f.syn)) 0) (is.eq ct.state (f: f.new)) drop]
        [(vmap meta.iifname { lo = accept; wan0 = jump "inbound_wan"; lan0 = accept; })];

      forward = add chain
        { type = f: f.filter; hook = f: f.forward; prio = f: f.filter; policy = f: f.drop; }
        [(vmap ct.state { established = accept; related = accept; invalid = drop; })]
        [(is.eq meta.iifname "lan0") accept];

      postrouting = add chain
        { type = f: f.nat; hook = f: f.postrouting; prio = f: f.filter; policy = f: f.accept; }
        [(is.eq meta.iifname "lan0") (is.eq meta.oifname "wan0") masquerade];
    };
  });
}
```

## Limitations / known incomplete areas

- `compile.nix` (JSON → `.nft` text) only handles tables/chains/rules. Sets, maps, flowtables, log, queue, vmap, and most statements are stubs (`throw "todo"`). Use the JSON path only.
- `networking.nftables` in nixpkgs does not natively accept JSON rulesets. You need to either write the JSON to a file and call `nft -j -f`, or use [nixos-router](https://github.com/chayleaf/nixos-router).
- Type checking validates JSON structure and expression contexts but not value types (e.g. it won't catch passing a port number where an IP address is expected).
