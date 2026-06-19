{
  MX = [
    {
      ttl = 3600;
      preference = 10;
      exchange = "tardisbox.example.com.";
    }
  ];
  TXT = [
    {
      ttl = 3600;
      data = "v=spf1 mx -all";
    }
  ];
  SRV = [
    {
      ttl = 3600;
      service = "autodiscover";
      proto = "tcp";
      priority = 1;
      weight = 1;
      port = 443;
      target = "tardisbox.example.com.";
    }
  ];
  subdomains = {
    "_smtp._tls" = {
      TXT = [
        {
          ttl = 3600;
          data = "v=TLSRPTv1; rua=mailto:tlsrpt@example.com";
        }
      ];
    };
    "_mta-sts" = {
      TXT = [
        {
          ttl = 3600;
          data = "v=STSv1; id=177315568879Z;";
        }
      ];
    };
    "_dmarc" = {
      TXT = [
        {
          ttl = 3600;
          data = "v=DMARC1; p=reject; rua=mailto:dmarc@example.com; ruf=mailto:dmarc@example.com; adkim=s; aspf=s";
        }
      ];
    };
    "autoconfig" = {
      CNAME = [
        {
          ttl = 3600;
          cname = "tardisbox.example.com.";
        }
      ];
    };
    "autodiscover" = {
      CNAME = [
        {
          ttl = 3600;
          cname = "tardisbox.example.com.";
        }
      ];
    };
    "mta-sts" = {
      CNAME = [
        {
          ttl = 3600;
          cname = "tardisbox.example.com.";
        }
      ];
    };
  };
}
