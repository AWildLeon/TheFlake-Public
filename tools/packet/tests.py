#!/usr/bin/env python3
import unittest

from packet_court import packet_from_args, simulate


def rule(chain, expr, family="inet", table="firewall"):
    return {"add": {"rule": {"family": family, "table": table, "chain": chain, "expr": expr}}}


def chain(name, policy=None, family="inet", table="firewall"):
    c = {"family": family, "table": table, "name": name}
    if policy:
        c.update({"type": "filter", "hook": name, "prio": 0, "policy": policy})
    return {"add": {"chain": c}}


BASE = {
    "enabled": True,
    "conntrack": "full",
    "inputPolicy": "drop",
    "forwardPolicy": "drop",
    "interfaces": ["lan", "guest", "wan"],
    "limitations": [],
    "rawRulesetOverride": False,
    "nat": {"outbound": [], "portForwards": [], "oneToOne": [], "vrfZones": {}, "hasRawExtraRules": False},
    "pbr": {"marks": [], "hasRawExtraRules": False},
}


def model_with(exprs):
    m = dict(BASE)
    m["nftables"] = {"nftables": [chain("forward", "drop"), chain("input", "drop")] + exprs}
    return m


class PacketCourtTests(unittest.TestCase):
    def test_allowed_forward(self):
        m = model_with([
            rule("forward", [
                {"match": {"left": {"meta": {"key": "iifname"}}, "op": "==", "right": "lan"}},
                {"match": {"left": {"meta": {"key": "oifname"}}, "op": "==", "right": "wan"}},
                {"accept": None},
            ])
        ])
        r = simulate(m, {"path": "forward", "iifname": "lan", "oifname": "wan", "proto": "tcp", "dport": 443, "ct_state": "new", "ct_mark": None})
        self.assertEqual(r.verdict, "ACCEPT")

    def test_dropped_by_policy(self):
        m = model_with([])
        r = simulate(m, {"path": "forward", "iifname": "guest", "oifname": "lan", "proto": "tcp", "dport": 22, "ct_state": "new", "ct_mark": None})
        self.assertEqual(r.verdict, "DROP")

    def test_dnat_then_accept(self):
        m = model_with([
            chain("prerouting", "accept", family="ip", table="nat"),
            rule("prerouting", [
                {"match": {"left": {"meta": {"key": "iifname"}}, "op": "==", "right": "wan"}},
                {"match": {"left": {"payload": {"field": "dport", "protocol": "tcp"}}, "op": "==", "right": 2222}},
                {"dnat": {"addr": "10.0.0.2", "port": 22}},
            ], family="ip", table="nat"),
            rule("forward", [
                {"match": {"left": {"meta": {"key": "iifname"}}, "op": "==", "right": "wan"}},
                {"match": {"left": {"payload": {"field": "daddr", "protocol": "ip"}}, "op": "==", "right": "10.0.0.2"}},
                {"match": {"left": {"payload": {"field": "dport", "protocol": "tcp"}}, "op": "==", "right": 22}},
                {"accept": None},
            ]),
        ])
        r = simulate(m, {"path": "forward", "iifname": "wan", "oifname": "lan", "daddr": "203.0.113.1", "proto": "tcp", "dport": 2222, "ct_state": "new", "ct_mark": None, "mark": None, "tcp_flags": []})
        self.assertEqual(r.verdict, "ACCEPT")

    def test_unknown_interface(self):
        m = model_with([])
        r = simulate(m, {"path": "forward", "iifname": "mystery", "oifname": "lan", "proto": "tcp", "dport": 22, "ct_state": "new", "ct_mark": None})
        self.assertEqual(r.verdict, "UNKNOWN")
        self.assertIn("unknown", r.unsupported)

    def test_unsupported_matching_rule_fails_closed(self):
        m = model_with([
            rule("forward", [
                {"match": {"left": {"meta": {"key": "iifname"}}, "op": "==", "right": "guest"}},
                {"limit": {"rate": 1, "per": "second"}},
                {"accept": None},
            ])
        ])
        r = simulate(m, {"path": "forward", "iifname": "guest", "oifname": "wan", "proto": "icmp", "ct_state": "new", "ct_mark": None})
        self.assertEqual(r.verdict, "UNKNOWN")
        self.assertIn("unsupported expression", r.unsupported)


if __name__ == "__main__":
    unittest.main()
