#!/usr/bin/env python3
"""Practical lh.firewall packet simulator (packet court).

This intentionally models only a conservative subset of the generated nftables JSON.
When a potentially matching rule contains unsupported expressions, verdict becomes
UNKNOWN rather than pretending certainty.
"""
from __future__ import annotations

import argparse
import fnmatch
import ipaddress
import json
import os
import subprocess
import sys
from dataclasses import dataclass, field
from typing import Any

TERMINALS = ("accept", "drop", "reject", "dnat", "snat", "masquerade", "notrack")
NON_TERMINAL = ("counter",)


@dataclass
class Result:
    verdict: str
    reasoning: list[str] = field(default_factory=list)
    matched_rule: dict[str, Any] | None = None
    warnings: list[str] = field(default_factory=list)
    unsupported: str | None = None


def sh(cmd: list[str]) -> str:
    return subprocess.check_output(cmd, text=True)


def flake_root() -> str:
    try:
        return sh(["git", "rev-parse", "--show-toplevel"]).strip()
    except Exception:
        return os.getcwd()


def load_model(args: argparse.Namespace) -> dict[str, Any]:
    if args.model_file:
        with open(args.model_file, encoding="utf-8") as f:
            return json.load(f)
    attr = f'nixosConfigurations."{args.host}".config.lh.firewall.analysisJson'
    raw = sh(["nix", "eval", "--raw", f"{args.flake}#{attr}"])
    return json.loads(raw)


def nft_items(model: dict[str, Any]) -> list[dict[str, Any]]:
    return model.get("nftables", {}).get("nftables", [])


def collect_chains(
    model: dict[str, Any], family: str = "inet", table: str = "firewall"
) -> tuple[dict[str, list[dict[str, Any]]], dict[str, dict[str, Any]]]:
    chains: dict[str, list[dict[str, Any]]] = {}
    meta: dict[str, dict[str, Any]] = {}
    for item in nft_items(model):
        add = item.get("add", {})
        if "chain" in add:
            ch = add["chain"]
            if ch.get("family") == family and ch.get("table") == table:
                name = ch["name"]
                chains.setdefault(name, [])
                meta[name] = ch
        elif "rule" in add:
            r = add["rule"]
            if r.get("family") == family and r.get("table") == table:
                chains.setdefault(r["chain"], []).append(r)
    return chains, meta


def norm_proto(p: str | None) -> str:
    if not p or p == "any":
        return "any"
    return {"icmpv6": "ipv6-icmp"}.get(p.lower(), p.lower())


def packet_from_args(args: argparse.Namespace, model: dict[str, Any]) -> dict[str, Any]:
    pkt = {
        "path": args.path,
        "iifname": args.from_iface,
        "oifname": args.to_iface,
        "saddr": args.src,
        "daddr": args.dst,
        "proto": norm_proto(args.proto),
        "sport": int(args.sport) if args.sport else None,
        "dport": int(args.dport) if args.dport else None,
        "ct_state": args.ct_state,
        "ct_mark": int(args.ct_mark) if args.ct_mark else None,
        "mark": int(args.mark) if args.mark else None,
        "tcp_flags": list(filter(None, (args.tcp_flags or "").replace(",", " ").split())),
    }
    # Helpful VRF-zone inference for this flake's generated rules: customer ingress
    # gets a ct mark in prerouting and forward rules accept oif wan + ct mark.
    if pkt["ct_mark"] is None:
        for name, z in model.get("nat", {}).get("vrfZones", {}).items():
            if pkt["oifname"] == z.get("wanInterface", "wan") and (
                pkt["iifname"] in z.get("ingressInterfaces", []) or pkt["iifname"] == f"vrf_{name}"
            ):
                pkt["ct_mark"] = z.get("mark")
    return pkt


def value_set(v: Any) -> list[Any]:
    if isinstance(v, dict) and "set" in v:
        return v["set"]
    return [v]


def match_scalar(actual: Any, right: Any) -> bool:
    vals = value_set(right)
    for v in vals:
        if isinstance(v, str) and isinstance(actual, str) and ("*" in v or "?" in v):
            if fnmatch.fnmatchcase(actual, v):
                return True
        elif isinstance(v, str) and isinstance(actual, str) and v.endswith("+"):
            if actual.startswith(v[:-1]):
                return True
        elif actual == v:
            return True
    return False


def ip_in_right(actual: str | None, right: Any) -> bool:
    if actual is None:
        return False
    try:
        ip = ipaddress.ip_address(actual)
    except ValueError:
        return False
    for v in value_set(right):
        if isinstance(v, dict) and "prefix" in v:
            p = v["prefix"]
            if ip in ipaddress.ip_network(f"{p['addr']}/{p['len']}", strict=False):
                return True
        elif isinstance(v, str):
            try:
                if "/" in v and ip in ipaddress.ip_network(v, strict=False):
                    return True
                if ip == ipaddress.ip_address(v):
                    return True
            except ValueError:
                pass
    return False


def field_for_left(left: dict[str, Any], pkt: dict[str, Any]) -> tuple[str | None, Any, bool]:
    if "meta" in left:
        key = left["meta"].get("key")
        if key == "iifname":
            return key, pkt.get("iifname"), False
        if key == "oifname":
            return key, pkt.get("oifname"), False
        if key == "mark":
            return key, pkt.get("mark"), False
    if "ct" in left:
        key = left["ct"].get("key")
        if key == "state":
            return "ct.state", pkt.get("ct_state"), False
        if key == "mark":
            return "ct.mark", pkt.get("ct_mark"), False
    if "payload" in left:
        p = left["payload"]
        proto = p.get("protocol")
        field = p.get("field")
        if field in ("protocol", "nexthdr"):
            return "proto", pkt.get("proto"), False
        if field in ("saddr", "daddr"):
            return field, pkt.get(field), True
        if field == "flags" and proto == "tcp":
            return "tcp.flags", pkt.get("tcp_flags"), False
        if field in ("sport", "dport"):
            # A tcp.dport matcher must not match a UDP packet with the same port.
            # th.dport is transport-header generic and applies to tcp/udp only.
            pkt_proto = pkt.get("proto")
            if proto in ("tcp", "udp") and pkt_proto not in ("any", proto):
                return field, "__nomatch__", False
            if proto == "th" and pkt_proto not in ("any", "tcp", "udp"):
                return field, "__nomatch__", False
            return field, pkt.get(field), False
        if field == "type":
            return f"{proto}.type", pkt.get("icmp_type"), False
    return None, None, False


def expr_matches(expr: dict[str, Any], pkt: dict[str, Any]) -> tuple[str, str | None]:
    """Return match|nomatch|unsupported."""
    if "match" not in expr:
        return "unsupported", f"unsupported expression {json.dumps(expr, sort_keys=True)}"
    m = expr["match"]
    op = m.get("op")
    if op not in ("==", "in"):
        return "unsupported", f"unsupported match operator {op} in {json.dumps(expr, sort_keys=True)}"
    field, actual, is_ip = field_for_left(m.get("left", {}), pkt)
    if field is None:
        return "unsupported", f"unsupported match left side {json.dumps(m.get('left'), sort_keys=True)}"
    if actual == "__nomatch__":
        return "nomatch", None
    if actual is None:
        return "unsupported", f"packet does not provide {field}, needed by {json.dumps(expr, sort_keys=True)}"
    if field == "proto" and actual == "any":
        return "unsupported", f"packet protocol is 'any', but rule needs protocol match {json.dumps(expr, sort_keys=True)}"
    if op == "in" and field == "tcp.flags":
        ok = m.get("right") in actual
    elif op == "in":
        ok = match_scalar(actual, m.get("right"))
    else:
        ok = ip_in_right(actual, m.get("right")) if is_ip else match_scalar(actual, m.get("right"))
    return ("match" if ok else "nomatch"), None


def vmap_action(expr: dict[str, Any], pkt: dict[str, Any]) -> tuple[str | None, str | None]:
    vm = expr.get("vmap")
    if not vm:
        return None, None
    field, actual, _ = field_for_left(vm.get("key", {}), pkt)
    if field is None:
        return "unsupported", f"unsupported vmap key {json.dumps(vm.get('key'), sort_keys=True)}"
    if actual is None:
        return "unsupported", f"packet does not provide {field}, needed by vmap"
    for k, verdict in vm.get("data", {}).get("set", []):
        if actual == k:
            for term in ("accept", "drop", "reject"):
                if term in verdict:
                    return term, None
            return "unsupported", f"unsupported vmap verdict {json.dumps(verdict, sort_keys=True)}"
    return "nomatch", None


def action_of(expr: dict[str, Any]) -> tuple[str | None, Any]:
    if "return" in expr:
        return "return", None
    for k in TERMINALS:
        if k in expr:
            return k, expr[k]
    if "jump" in expr:
        return "jump", expr["jump"].get("target")
    if "goto" in expr:
        return "goto", expr["goto"].get("target")
    if "mangle" in expr:
        return "mangle", expr["mangle"]
    for k in NON_TERMINAL:
        if k in expr:
            return "nonterminal", None
    return None, None


def rule_has_verdict_or_transfer(rule: dict[str, Any]) -> bool:
    for expr in rule.get("expr", []):
        if any(k in expr for k in ("accept", "drop", "reject", "dnat", "snat", "masquerade", "jump", "goto", "return")):
            return True
    return False


def eval_rule(rule: dict[str, Any], pkt: dict[str, Any]) -> tuple[str, Any, str | None]:
    potentially_verdicting = rule_has_verdict_or_transfer(rule)
    for expr in rule.get("expr", []):
        vact, vwhy = vmap_action(expr, pkt)
        if vact == "nomatch":
            return "nomatch", None, None
        if vact == "unsupported":
            return "unsupported", None, vwhy
        if vact:
            return vact, None, None
        act, data = action_of(expr)
        if act:
            return act, data, None
        status, why = expr_matches(expr, pkt)
        if status == "nomatch":
            return "nomatch", None, None
        if status == "unsupported":
            if potentially_verdicting:
                return "unsupported", None, why
            return "partial", None, why
    return "continue", None, "rule has no modeled verdict/action"


def simulate_chain(chains: dict[str, list[dict[str, Any]]], meta: dict[str, dict[str, Any]], chain: str, pkt: dict[str, Any], depth=0) -> Result:
    if depth > 12:
        return Result("UNKNOWN", unsupported="jump recursion too deep")
    reasoning: list[str] = [f"Enter chain {chain}."]
    for idx, rule in enumerate(chains.get(chain, []), 1):
        act, data, why = eval_rule(rule, pkt)
        if act == "nomatch":
            continue
        if act == "unsupported":
            reasoning.append(f"Rule {chain}#{idx} may apply but is unsupported.")
            return Result("UNKNOWN", reasoning, rule, unsupported=why)
        if act == "partial":
            reasoning.append(f"Rule {chain}#{idx} has unsupported non-verdict matching/action; continuing conservatively: {why}")
            continue
        if act == "return":
            reasoning.append(f"Rule {chain}#{idx} matched: RETURN.")
            return Result("RETURN", reasoning, rule)
        if act in ("jump", "goto"):
            reasoning.append(f"Rule {chain}#{idx} matched: {act} {data}.")
            sub = simulate_chain(chains, meta, data, pkt, depth + 1)
            reasoning.extend("  " + x for x in sub.reasoning)
            if sub.verdict == "RETURN":
                continue
            sub.reasoning = reasoning
            return sub
        if act in ("accept", "drop", "reject"):
            reasoning.append(f"Rule {chain}#{idx} matched: {act.upper()}.")
            return Result(act.upper(), reasoning, rule)
        if act in ("dnat", "snat", "masquerade"):
            reasoning.append(f"Rule {chain}#{idx} matched NAT action {act}.")
            return Result("NAT", reasoning, rule, unsupported="NAT translation is reported but not fully simulated")
        if act == "mangle":
            reasoning.append(f"Rule {chain}#{idx} matched: {apply_mangle(pkt, data)}; continuing.")
            continue
        if act in ("notrack", "continue"):
            reasoning.append(f"Rule {chain}#{idx} matched non-verdict action {act}; continuing/partially modeled.")
            continue
    pol = meta.get(chain, {}).get("policy")
    if pol:
        reasoning.append(f"No rule gave a verdict. Chain policy: {pol.upper()}.")
        return Result(pol.upper(), reasoning)
    reasoning.append("End of regular chain; returning to caller.")
    return Result("RETURN", reasoning)


def add_meta_match_interfaces(model: dict[str, Any], s: set[str]) -> None:
    def add_right(right: Any) -> None:
        for v in value_set(right):
            if isinstance(v, str) and "*" not in v and "?" not in v:
                s.add(v)
    for item in nft_items(model):
        rule_obj = item.get("add", {}).get("rule")
        if not rule_obj:
            continue
        for expr in rule_obj.get("expr", []):
            m = expr.get("match")
            if not m:
                continue
            left = m.get("left", {})
            if left.get("meta", {}).get("key") in ("iifname", "oifname"):
                add_right(m.get("right"))


def iface_known(name: str, known: set[str]) -> bool:
    if name in known:
        return True
    return any(k.endswith("+") and name.startswith(k[:-1]) for k in known)


def known_interfaces(model: dict[str, Any]) -> set[str]:
    s = set(model.get("interfaces", [])) | {"lo"}
    nat = model.get("nat", {})
    for ob in nat.get("outbound", []):
        s.add(ob.get("oifname"))
    for pf in nat.get("portForwards", []):
        s.add(pf.get("iifname"))
    for zname, z in nat.get("vrfZones", {}).items():
        s.add(z.get("wanInterface", "wan"))
        s.add(f"vrf_{zname}")
        s.update(z.get("ingressInterfaces", []))
    add_meta_match_interfaces(model, s)
    return {x for x in s if x}


def eval_addr_expr(expr: Any, pkt: dict[str, Any]) -> str | None:
    if expr is None:
        return None
    if isinstance(expr, str):
        return expr
    # notnft netmap helper emits: (payload addr & hostmask) | baseaddr.
    if isinstance(expr, dict) and "|" in expr:
        left, base = expr["|"]
        if isinstance(left, dict) and "&" in left and isinstance(base, str):
            src_expr, mask = left["&"]
            if isinstance(src_expr, dict) and "payload" in src_expr and isinstance(mask, str):
                field = src_expr["payload"].get("field")
                actual = pkt.get(field)
                if actual:
                    try:
                        return str(ipaddress.ip_address(int(ipaddress.ip_address(actual)) & int(ipaddress.ip_address(mask)) | int(ipaddress.ip_address(base))))
                    except ValueError:
                        return None
    return None


def apply_nat_action(pkt: dict[str, Any], action: str, data: Any) -> str:
    if action == "dnat":
        if isinstance(data, dict):
            addr = eval_addr_expr(data.get("addr"), pkt)
            if addr is not None:
                pkt["daddr"] = addr
            if data.get("port") is not None:
                pkt["dport"] = int(data["port"])
            return f"DNAT to {addr or '<unsupported-expr>'}:{data.get('port', '<same>')}"
        return "DNAT (unparsed target)"
    if action == "snat":
        if isinstance(data, dict) and data.get("addr") is not None:
            addr = eval_addr_expr(data.get("addr"), pkt)
            if addr is not None:
                pkt["saddr"] = addr
            return f"SNAT to {addr or '<unsupported-expr>'}"
        return "SNAT (unparsed target)"
    if action == "masquerade":
        return "MASQUERADE (source address becomes egress interface address; exact address not modeled)"
    return action.upper()


def apply_mangle(pkt: dict[str, Any], data: Any) -> str:
    if isinstance(data, dict):
        key = data.get("key", {})
        value = data.get("value")
        if key == {"meta": {"key": "mark"}}:
            pkt["mark"] = value
            return f"set meta mark {value}"
        if key == {"ct": {"key": "mark"}}:
            pkt["ct_mark"] = value
            return f"set ct mark {value}"
    return f"unsupported mangle {json.dumps(data, sort_keys=True)}"


def simulate_mangle_chain(model: dict[str, Any], pkt: dict[str, Any], chain: str) -> tuple[list[str], list[str], str | None]:
    notes: list[str] = []
    warnings: list[str] = []
    unsupported: str | None = None
    chains, _meta = collect_chains(model, "ip", "mangle")
    for idx, rule in enumerate(chains.get(chain, []), 1):
        act, data, why = eval_rule(rule, pkt)
        if act == "nomatch":
            continue
        if act == "unsupported":
            unsupported = why
            notes.append(f"Mangle {chain} rule #{idx} may apply but is unsupported.")
            break
        if act == "partial":
            warnings.append(f"Mangle {chain} rule #{idx} has unsupported non-verdict expression; ignored for verdict: {why}")
            continue
        if act == "mangle":
            notes.append(f"Mangle {chain} rule #{idx} matched: {apply_mangle(pkt, data)}.")
            continue
        if act in ("accept", "drop", "reject"):
            notes.append(f"Mangle {chain} rule #{idx} returned verdict {act.upper()}.")
            break
        if act in ("jump", "goto", "dnat", "snat", "masquerade", "notrack", "continue"):
            warnings.append(f"Mangle {chain} rule #{idx} used action {act}; partially modeled.")
    return notes, warnings, unsupported


def simulate_nat_chain(model: dict[str, Any], pkt: dict[str, Any], chain: str) -> tuple[list[str], list[str], str | None]:
    notes: list[str] = []
    warnings: list[str] = []
    unsupported: str | None = None
    chains, _meta = collect_chains(model, "ip", "nat")
    for idx, rule in enumerate(chains.get(chain, []), 1):
        act, data, why = eval_rule(rule, pkt)
        if act == "nomatch":
            continue
        if act == "unsupported":
            unsupported = why
            notes.append(f"NAT {chain} rule #{idx} may apply but is unsupported.")
            break
        if act == "partial":
            warnings.append(f"NAT {chain} rule #{idx} has unsupported non-verdict expression; ignored for verdict: {why}")
            continue
        if act in ("dnat", "snat", "masquerade"):
            notes.append(f"NAT {chain} rule #{idx} matched: {apply_nat_action(pkt, act, data)}.")
            # nft nat chains use first translation binding for a flow.
            break
        if act in ("accept", "drop", "reject"):
            notes.append(f"NAT {chain} rule #{idx} returned verdict {act.upper()} (unusual in nat path).")
            break
        if act == "mangle":
            notes.append(f"NAT {chain} rule #{idx} matched: {apply_mangle(pkt, data)}.")
            continue
        if act in ("notrack", "continue"):
            warnings.append(f"NAT {chain} rule #{idx} used non-NAT action {act}; partially modeled.")
    return notes, warnings, unsupported


def simulate(model: dict[str, Any], pkt: dict[str, Any]) -> Result:
    if not model.get("enabled"):
        return Result("UNKNOWN", unsupported="lh.firewall is not enabled for this host")
    warnings = list(model.get("limitations", []))
    if model.get("rawRulesetOverride"):
        warnings.append("Host uses lh.firewall.ruleset raw override; model may be incomplete.")
    if model.get("nat", {}).get("hasRawExtraRules") or model.get("pbr", {}).get("hasRawExtraRules"):
        warnings.append("Host has raw NAT/PBR extra rules that are not fully modeled.")
    ki = known_interfaces(model)
    for label, name in (("from", pkt.get("iifname")), ("to", pkt.get("oifname"))):
        if name and not iface_known(name, ki):
            return Result("UNKNOWN", [f"Unknown {label} interface/zone: {name}."], warnings=warnings, unsupported="unknown interface/zone")
    mangle_notes, mangle_warnings, mangle_unsupported = simulate_mangle_chain(model, pkt, "prerouting")
    warnings.extend(mangle_warnings)
    if mangle_unsupported:
        return Result("UNKNOWN", mangle_notes, warnings=warnings, unsupported=mangle_unsupported)

    pre_notes, pre_warnings, pre_unsupported = simulate_nat_chain(model, pkt, "prerouting")
    warnings.extend(pre_warnings)
    if pre_unsupported:
        return Result("UNKNOWN", mangle_notes + pre_notes, warnings=warnings, unsupported=pre_unsupported)

    chains, meta = collect_chains(model)
    chain = "forward" if pkt["path"] == "forward" else "input"
    r = simulate_chain(chains, meta, chain, pkt)
    r.reasoning = mangle_notes + pre_notes + r.reasoning
    if r.verdict == "ACCEPT" and pkt["path"] == "forward":
        post_notes, post_warnings, post_unsupported = simulate_nat_chain(model, pkt, "postrouting")
        r.reasoning.extend(post_notes)
        warnings.extend(post_warnings)
        if post_unsupported:
            r.verdict = "UNKNOWN"
            r.unsupported = post_unsupported
    r.warnings = warnings
    if r.verdict == "RETURN":
        r.verdict = "UNKNOWN"
        r.unsupported = "top-level chain returned without policy"
    return r


def print_text(res: Result, args: argparse.Namespace, pkt: dict[str, Any]) -> None:
    print(f"Verdict: {res.verdict}")
    if res.unsupported:
        print("\nReason:")
        print(res.unsupported)
    print("\nReasoning:")
    print(f"1. Packet path: {pkt['path']} from {pkt.get('iifname')} to {pkt.get('oifname')} proto={pkt.get('proto')} dport={pkt.get('dport')}")
    for i, line in enumerate(res.reasoning, 2):
        print(f"{i}. {line}")
    if res.matched_rule:
        print("\nMatched rule:")
        print(json.dumps(res.matched_rule.get("expr", res.matched_rule), indent=2, sort_keys=True))
    if res.warnings:
        print("\nWarnings / limitations:")
        for w in res.warnings:
            print(f"- {w}")


def examples(host: str) -> None:
    print(f"""Examples:
  lhflake packet {host} --path forward --from vrf_leon --to leon --proto tcp --dport 22
  lhflake packet {host} --path forward --from wan --to vrf_leon --dst 10.1.0.2 --proto tcp --dport 22
  lhflake packet {host} --path input --from vrf_leon --proto tcp --dport 179
  lhflake packet {host} --list-interfaces
  lhflake packet {host} --dump-model | jq .
""")


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="lh.firewall packet simulator / packet court")
    p.add_argument("host", nargs="?", help="host key, e.g. router.home.core")
    p.add_argument("--flake", default=flake_root())
    p.add_argument("--model-file", help=argparse.SUPPRESS)
    p.add_argument("--path", choices=["forward", "input"], default="forward")
    p.add_argument("--from", dest="from_iface")
    p.add_argument("--to", dest="to_iface")
    p.add_argument("--src")
    p.add_argument("--dst")
    p.add_argument("--proto", default="any", choices=["tcp", "udp", "icmp", "icmpv6", "ipv6-icmp", "any"])
    p.add_argument("--sport")
    p.add_argument("--dport")
    p.add_argument("--ct-state", choices=["new", "established", "related", "invalid"], default="new")
    p.add_argument("--ct-mark")
    p.add_argument("--mark", help="packet meta/fw mark")
    p.add_argument("--tcp-flags", help="TCP flags, comma or space separated, e.g. syn or 'syn ack'")
    p.add_argument("--json", action="store_true")
    p.add_argument("--examples", action="store_true")
    p.add_argument("--list-zones", action="store_true")
    p.add_argument("--list-interfaces", action="store_true")
    p.add_argument("--dump-model", action="store_true")
    args = p.parse_args(argv)
    if not args.host and not args.model_file:
        p.error("host is required unless --model-file is used")
    if args.examples:
        examples(args.host or "<host>")
        return 0
    model = load_model(args)
    if args.dump_model:
        print(json.dumps(model, indent=2, sort_keys=True))
        return 0
    if args.list_interfaces:
        for x in sorted(known_interfaces(model)):
            print(x)
        return 0
    if args.list_zones:
        for x in sorted(model.get("nat", {}).get("vrfZones", {}).keys()):
            print(x)
        return 0
    if args.path == "forward" and (not args.from_iface or not args.to_iface):
        p.error("forward path requires --from and --to")
    if args.path == "input" and not args.from_iface:
        p.error("input path requires --from")
    pkt = packet_from_args(args, model)
    res = simulate(model, pkt)
    if args.json:
        print(json.dumps({"verdict": res.verdict, "reasoning": res.reasoning, "warnings": res.warnings, "unsupported": res.unsupported, "packet": pkt, "matchedRule": res.matched_rule}, indent=2, sort_keys=True))
    else:
        print_text(res, args, pkt)
    return 2 if res.verdict == "UNKNOWN" else 0


if __name__ == "__main__":
    raise SystemExit(main())
