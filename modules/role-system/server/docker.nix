{
  pkgs,
  lib,
  config,
  ...
}:
{

  options.lh.roleSystem.role.server.docker = {
    enable = lib.mkEnableOption "Enable Docker with server-specific settings.";
  };

  config =
    lib.mkIf
      (config.lh.roleSystem.systemType == "server" && config.lh.roleSystem.role.server.docker.enable)
      {

        virtualisation.docker = {
          enable = true;
          liveRestore = false;
          autoPrune.enable = true;
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
        networking = {

          # Dont Intevene with Docker's networking
          firewall.enable = false;
          nftables.enable = false;
        };

        lh.services.traefik = {
          enable = lib.mkDefault true;

        };

        # If clatd is active we need to start docker after it
        systemd.services.docker.unitConfig = lib.mkIf config.services.clatd.enable {
          Wants = lib.mkAfter [ "clatd.service" ];
          After = lib.mkAfter [ "clatd.service" ];
        };
      };
}
