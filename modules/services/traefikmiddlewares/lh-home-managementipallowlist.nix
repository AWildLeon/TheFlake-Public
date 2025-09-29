{ lib, config, ... }: {

  lh.services.traefik.dynamicConfig =
    lib.mkIf config.lh.services.traefik.enable {

      http.middlewares."lh-home-managementipallowlist".ipAllowList.sourceRange =
        [
          "10.0.0.0/24"
          "10.21.21.0/24"
          "2a14:47c0:e002:0::/64"
          "2a14:47c0:e002:2121::/64"
        ];

    };
}
