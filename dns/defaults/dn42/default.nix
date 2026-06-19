{
  lh,
  withLHMailDn42 ? false,
  ...
}:
lh.lib.dns.mergeZone (if withLHMailDn42 then (import ./lhmaildn42.nix) else { }) {
  SOA = import ./soa.nix { serial = 2024063028; } // {
    ttl = 3600;
  };
  NS = import ./ns.nix;

  HTTPS = [
    {
      ttl = 600;
      svcPriority = 1;
      targetName = ".";
      alpn = [ "h2" ];
    }
  ];

  subdomains = {
    "*" = {
      HTTPS = [
        {
          ttl = 600;
          svcPriority = 1;
          targetName = ".";
          alpn = [ "h2" ];
        }
      ];
    };
  };
}
