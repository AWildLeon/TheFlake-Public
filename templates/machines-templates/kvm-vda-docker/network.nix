{ lib, self, ... }:
let
  hostPart = "XX";
  hostName = "nixos";
  fqdn = "${hostName}.onlh.de";
in
{

  lh.networking.dnsTemplates = {
    enable = true;
    server = "home";
  };

  networking = {
    inherit hostName fqdn;
    useDHCP = lib.mkForce false;
    dhcpcd.enable = lib.mkForce false;
  };

  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;
    networks = {
      ens18 = {
        matchConfig.Name = "ens18";
        networkConfig.IPv6AcceptRA = false;
        address = [
          "2a14:47c0:e002:4::${hostPart}/64"
          "10.0.4.${hostPart}/24"
        ];

        gateway = [
          "fe80::1"
        ];

        routes = [
          {
            Gateway = "10.21.255.255";
            GatewayOnLink = true;
          }
        ];
      };
    };
  };
}
