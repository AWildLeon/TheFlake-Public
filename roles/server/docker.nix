{ pkgs
, arion
, lib
, ...
}:
{

  imports = [
    arion.nixosModules.arion
  ];

  virtualisation.docker = {
    enable = true;
    liveRestore = false;
    autoPrune.enable = true;
    package = pkgs.docker_28;
    daemon.settings = {
      ipv6 = true;
      experimental = true;
      fixed-cidr-v6 = "fd2a:51fd:c4b9::/48";
      ip6tables = true;
      "default-address-pools" = [
        {
          "base" = "172.16.0.0/12";
          "size" = 26;
        }
        {
          "base" = "fd1c:355e:1995::/48";
          "size" = 80;
        }
      ];
    };

  };

  boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 0;

  # Dont Intevene with Docker's networking
  networking.firewall.enable = false;

  lh.services.traefik = {
    enable = lib.mkDefault true;

  };

  virtualisation.arion = {
    backend = "docker";
  };

  environment.systemPackages = [
    arion.packages.${pkgs.system}.arion
  ];
}
