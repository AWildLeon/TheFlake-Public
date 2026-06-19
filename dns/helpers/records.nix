# DNS record creation from machine configurations
# Scope: Create A, AAAA, and host records from NixOS machine network configs
{ inputs, network }:
let
  inherit (inputs.dns.lib.combinators)
    a
    aaaa
    host
    ;
in
rec {
  # Create an A record from a machine's IPv4 address
  aFromMachine =
    {
      machine,
      interface,
      ttl ? null,
      scope ? "preferPublic",
    }:
    let
      address = network.getMachineInterfaceAddress {
        family = "ipv4";
        inherit machine interface scope;
      };
    in
    if ttl == null then a address else (inputs.dns.lib.combinators.ttl ttl (a address));

  # Create an AAAA record from a machine's IPv6 address
  aaaaFromMachine =
    {
      machine,
      interface,
      ttl ? null,
      scope ? "preferPublic",
    }:
    let
      address = network.getMachineInterfaceAddress {
        family = "ipv6";
        inherit machine interface scope;
      };
    in
    if ttl == null then aaaa address else (inputs.dns.lib.combinators.ttl ttl (aaaa address));

  # Create both A and AAAA records from a machine's addresses
  hostFromMachine =
    {
      machine,
      interface,
      ttl ? null,
      scope ? "preferPublic",
    }:
    let
      ipv4 = network.getMachineInterfaceAddress {
        family = "ipv4";
        inherit machine interface scope;
      };
      ipv6 = network.getMachineInterfaceAddress {
        family = "ipv6";
        inherit machine interface scope;
      };
    in
    if ttl == null then
      host ipv4 ipv6
    else
      {
        A = [ (inputs.dns.lib.combinators.ttl ttl (a ipv4)) ];
        AAAA = [ (inputs.dns.lib.combinators.ttl ttl (aaaa ipv6)) ];
      };
}
