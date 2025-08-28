{ ... }:
{
  imports = [
    ./traefik.nix
    ./nameserver.nix
    ./nginx.nix
    ./grafana.nix
    ../helper/jail.nix
  ];

  systemd.tmpfiles.rules = [
    "d /var/run/jails/ 0755 root root -"
  ];
}
