{
  lh,
  withLhmail ? false,
  withAnonaddy ? false,
  ...
}:
lh.lib.dns.mergeZone
  (
    if withLhmail then
      (import ./lhmail.nix)
    else if withAnonaddy then
      (import ./anonaddy.nix)
    else
      { }
  )
  {
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

    CAA = [
      {
        ttl = 3600;
        issuerCritical = false;
        tag = "issuewild";
        value = "letsencrypt.org";
      }
      {
        ttl = 3600;
        issuerCritical = false;
        tag = "issue";
        value = "letsencrypt.org";
      }
      {
        ttl = 3600;
        issuerCritical = false;
        tag = "iodef";
        value = "mailto:ssl@example.com";
      }
    ];

    subdomains = {
      "*" = {
        CAA = [
          {
            ttl = 3600;
            issuerCritical = false;
            tag = "issuewild";
            value = "letsencrypt.org";
          }
          {
            ttl = 3600;
            issuerCritical = false;
            tag = "issue";
            value = "letsencrypt.org";
          }
        ];
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
