{
  serial ? throw "Serial number is required",
}:
{
  ttl = 900;
  nameServer = "ns1.example.dn42.";
  adminEmail = "dns@example.com";
  inherit serial;
  refresh = 3600;
  retry = 900;
  expire = 604800;
  minimum = 900;
}
