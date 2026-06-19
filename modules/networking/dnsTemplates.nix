{ lib, config, ... }:
let
  cfg = config.lh.networking.dnsTemplates;
in
{
  options.lh.networking.dnsTemplates = {
    enable = lib.mkEnableOption "DNS templates";
    server = lib.mkOption {
      type = lib.types.enum [
        "ita_cogent"
        "home"
        "quad9"
        "google"
        "cloudflare"
      ];
      default = "quad9";
      description = "Select a DNS server.";
    };
  };

  config = lib.mkIf cfg.enable {

    lh.router.radvd = {
      dns =
        lib.mkDefault
          {
            ita_cogent = [ "2a14:47c0:e001:1010::10" ];
            home = [ "2a14:47c0:e002:1010::10" ];
            quad9 = [ "2620:fe::fe" ];
            google = [ "2001:4860:4860::8888" ];
            cloudflare = [ "2606:4700:4700::1111" ];
          }
          .${cfg.server};
    };

    networking.nameservers =
      {
        ita_cogent = [
          "2a14:47c0:e001:1010::10"
          "10.10.10.10"
        ];
        home = [
          "2a14:47c0:e002:1010::10"
          "10.10.10.10"
        ];
        quad9 = [
          "2620:fe::fe"
          "9.9.9.9"
          "149.112.112.112"
        ];
        google = [
          "2001:4860:4860::8888"
          "8.8.8.8"
          "8.8.4.4"
        ];
        cloudflare = [
          "2606:4700:4700::1111"
          "1.1.1.1"
          "1.0.0.1"
        ];
      }
      .${cfg.server};

  };
}
