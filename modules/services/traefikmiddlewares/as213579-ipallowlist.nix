{ lib, config, ... }:
{

  lh.services.traefik.dynamicConfig = lib.mkIf config.lh.services.traefik.enable {

    http.middlewares."as213579-ipallowlist".ipAllowList.sourceRange = [
      "185.140.54.0/24"
      "2a14:47c0:e001::/48" # Cogent
      "2a14:47c0:e002::/48" # Home
      "2a14:47c0:e003::/48" # ITA-POP
      "2a14:47c0:e005::/48" # ETH-POP
      "2a14:47c0:e047::/48" # Home-DMZ
    ];

  };
}
