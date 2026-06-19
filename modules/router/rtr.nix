{
  lib,
  pkgs,
  config,
  ...
}:

let
  cfg = config.lh.router.rpki;
in
{

  options.lh.router.rpki = {
    enable = lib.mkEnableOption "Enable RPKI validation with Routinator.";
    bind = lib.mkOption {
      type = lib.types.str;
      default = "[::1]:8282";
      description = "Address and port to bind the RPKI to Router Protocol daemon.";
    };
    bindMetrics = lib.mkOption {
      type = lib.types.str;
      default = "[::1]:9847";
      description = "Address and port to bind the RPKI to Router Protocol metrics.";
    };
    dn42 = {
      enable = lib.mkEnableOption "Enable DN42-specific RPKI configuration.";
      bind = lib.mkOption {
        type = lib.types.str;
        default = "[::1]:8283";
        description = "Address and port to bind the RPKI to Router Protocol daemon for DN42.";
      };
      bindMetrics = lib.mkOption {
        type = lib.types.str;
        default = "[::1]:9848";
        description = "Address and port to bind the RPKI to Router Protocol metrics for DN42.";
      };
    };
  };

  config = {
    systemd.services.stayrtr = lib.mkIf cfg.enable {
      description = "stayrtr RPKI to Router Protocol Daemon";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.stayrtr}/bin/stayrtr -bind [::1]:8282 -metrics.addr [::1]:9847";
        Restart = "on-failure";
        RestartSec = "10s";
        # AmbientCapabilities = [ "CAP_NET_ADMIN" ];
      };
      wantedBy = [ "multi-user.target" ];
    };

    systemd.services.stayrtr-dn42 = lib.mkIf cfg.dn42.enable {
      description = "stayrtr RPKI to Router Protocol Daemon for DN42";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.stayrtr}/bin/stayrtr -bind [::1]:8283 -metrics.addr [::1]:9848 -cache https://kioubit-roa.dn42.dev/?type=json";
        Restart = "on-failure";
        RestartSec = "10s";
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}
