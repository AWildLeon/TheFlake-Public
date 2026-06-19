{
  MX = [
    {
      ttl = 3600;
      preference = 10;
      exchange = "addy.example.com.";
    }
  ];
  TXT = [
    {
      ttl = 3600;
      data = "v=spf1 mx -all";
    }
  ];
  subdomains = {
    "_dmarc" = {
      TXT = [
        {
          ttl = 3600;
          data = "v=DMARC1; p=quarantine; adkim=s";
        }
      ];
    };
    "default._domainkey" = {
      CNAME = [
        {
          ttl = 3600;
          cname = "default._domainkey.addy.example.com.";
        }
      ];
    };
  };
}
