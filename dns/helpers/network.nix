# Network address extraction utilities
# Scope: Extract IP addresses from NixOS machine configurations
{ inputs }:
let
  normalizeFamily =
    family:
    if family == 4 || family == "4" || family == "ipv4" || family == "inet" then
      "ipv4"
    else if family == 6 || family == "6" || family == "ipv6" || family == "inet6" then
      "ipv6"
    else
      throw "Invalid address family '${toString family}'. Use one of: 4, 6, ipv4, ipv6, inet, inet6.";

  stripPrefixLength =
    addr:
    if !builtins.isString addr then
      null
    else
      let
        m = builtins.match "^([^/]+)(/.*)?$" addr;
      in
      if m == null then null else builtins.elemAt m 0;

  isIPv4 = addr: builtins.isString addr && builtins.match "^[0-9.]+$" addr != null;
  isIPv6 = addr: builtins.isString addr && builtins.match ".*:.*" addr != null;

  # DN42 ranges: 172.20.0.0/14 (IPv4), fd00::/8 (IPv6 ULA)
  isDn42 =
    addr:
    if isIPv4 addr then
      builtins.match "^172\\.2[0-3]\\.[0-9]+\\.[0-9]+$" addr != null
    else if isIPv6 addr then
      builtins.match "^[Ff][Dd][0-9a-fA-F][0-9a-fA-F]:.*" addr != null
    else
      false;

  # scope: "dn42" | "public" | "preferPrivate" | "preferPublic"
  # dn42        – only DN42 addresses
  # public      – only public (non-DN42) addresses
  # preferPrivate – DN42 if any exist, otherwise public
  # preferPublic  – public if any exist, otherwise DN42
  applyScope =
    scope: addrs:
    let
      dn42Addrs = builtins.filter isDn42 addrs;
      publicAddrs = builtins.filter (a: !isDn42 a) addrs;
    in
    if scope == "dn42" then
      dn42Addrs
    else if scope == "public" then
      publicAddrs
    else if scope == "preferPrivate" then
      if dn42Addrs != [ ] then dn42Addrs else publicAddrs
    else if scope == "preferPublic" then
      if publicAddrs != [ ] then publicAddrs else dn42Addrs
    else
      throw "Invalid scope '${scope}'. Use one of: dn42, public, preferPrivate, preferPublic.";

  pickByFamily =
    family: addrs:
    let
      pred = if family == "ipv4" then isIPv4 else isIPv6;
    in
    builtins.filter pred addrs;

  fromSystemdNetwork =
    {
      cfg,
      interface,
      family,
    }:
    let
      networks = cfg.systemd.network.networks or { };
      names = builtins.attrNames networks;
      matchingNames = builtins.filter (
        n: n == interface || (((networks.${n}.matchConfig or { }).Name or null) == interface)
      ) names;
      matching = builtins.map (n: networks.${n}) matchingNames;

      fromAddressList = net: builtins.map stripPrefixLength (net.address or [ ]);
      fromAddresses =
        net:
        builtins.map (
          a:
          stripPrefixLength (
            if builtins.hasAttr "Address" a then
              a.Address
            else if builtins.hasAttr "address" a then
              a.address
            else
              null
          )
        ) (net.addresses or [ ]);

      all = builtins.concatLists (builtins.map (net: fromAddressList net ++ fromAddresses net) matching);
    in
    pickByFamily family (builtins.filter (a: a != null) all);

  fromLegacyNetwork =
    {
      cfg,
      interface,
      family,
    }:
    let
      interfaces = cfg.networking.interfaces or { };
      iface = if builtins.hasAttr interface interfaces then interfaces.${interface} else { };
      familyCfg = if builtins.hasAttr family iface then iface.${family} else { };
      addrs = builtins.map (a: a.address or null) (familyCfg.addresses or [ ]);
    in
    builtins.filter (a: a != null) addrs;
in
rec {
  # Get an IP address from a machine's network interface configuration
  getMachineInterfaceAddress =
    {
      family,
      machine,
      interface,
      # "preferPublic" | "preferPrivate" | "dn42" | "public"
      scope ? "preferPublic",
    }:
    let
      family' = normalizeFamily family;
      systems = inputs.self.nixosConfigurations or { };
      cfg =
        if builtins.hasAttr machine systems then
          systems.${machine}.config
        else
          throw "Machine '${machine}' not found in inputs.self.nixosConfigurations.";

      systemdAddrs = fromSystemdNetwork {
        inherit cfg interface;
        family = family';
      };
      legacyAddrs = fromLegacyNetwork {
        inherit cfg interface;
        family = family';
      };
      matches = applyScope scope (systemdAddrs ++ legacyAddrs);
    in
    if matches != [ ] then
      builtins.elemAt matches 0
    else
      throw "No ${family'} address found for interface '${interface}' on machine '${machine}'.";

  # Alias for getMachineInterfaceAddress
  getMachineAddress = getMachineInterfaceAddress;
}
