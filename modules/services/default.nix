{ glance-ical-events, copyparty, ... }: {
  imports = [
    ./traefik.nix
    ./nameserver.nix
    ./nginx.nix
    ./grafana.nix
    ./gitea.nix
    ../helper/jail.nix
    ./glanceapp.nix
    ./copyparty.nix
    ./traefikmiddlewares/default.nix
    ./databases/mysql.nix
    ./recursivedns.nix
    ./bootserver.nix
    ./gotify.nix
    ./uptime-kuma.nix
    glance-ical-events.nixosModules.default
    copyparty.nixosModules.default
  ];

  nixpkgs.overlays = [ copyparty.overlays.default ];

  systemd.tmpfiles.rules = [ "d /run/jails/ 0755 root root -" ];
}
