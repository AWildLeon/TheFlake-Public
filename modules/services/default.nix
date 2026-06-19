{ ... }:
{
  imports = [
    ./traefik.nix
    ./nameserver.nix
    ./nginx.nix
    ./grafana.nix
    ./gitea.nix
    ../helper/jail.nix
    ./glanceapp.nix
    ./traefikmiddlewares/default.nix
    ./databases/mysql.nix
    ./databases/postgres.nix
    ./recursivedns.nix
    ./bootserver.nix
    ./gotify.nix
    ./uptime-kuma.nix
    ./vaultwarden.nix
    ./rustdesk-server.nix
    ./wordpress.nix
    ./zammad.nix
    ./monero/monero.nix
  ];

  systemd.tmpfiles.rules = [ "d /run/jails/ 0755 root root -" ];
}
