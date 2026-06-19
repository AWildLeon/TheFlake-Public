{ lib, self, ... }:
let
  hostPart = "XX";
  hostName = "nixos";
  fqdn = "${hostName}.nodes.lhnetworks.de";
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
          "2a14:47c0:e047::${hostPart}/64"
          "185.140.54.${hostPart}/26"
        ];

        gateway = [
          "fe80::1"
          "185.140.54.1"
        ];
      };
    };
  };
}
