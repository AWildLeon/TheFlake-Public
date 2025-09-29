{ lib, config, ... }: {

  lh.services.traefik.dynamicConfig =
    lib.mkIf config.lh.services.traefik.enable {
      http.middlewares.securityheaders.headers = {
        stsSeconds = 15552000;
        customRequestHeaders = { "X-Forwarded-Proto" = "https"; };
        stsPreload = true;
        stsIncludeSubdomains = true;
      };
    };

}
