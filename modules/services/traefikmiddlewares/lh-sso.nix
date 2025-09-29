{ lib, config, ... }: {

  lh.services.traefik.dynamicConfig =
    lib.mkIf config.lh.services.traefik.enable {
      http.middlewares."lh-sso" = {
        forwardAuth = {
          address = "https://sso.onlh.de/outpost.goauthentik.io/auth/traefik";
          authResponseHeaders = [
            "X-authentik-username"
            "X-authentik-groups"
            "X-authentik-email"
            "X-authentik-name"
            "X-authentik-uid"
            "X-authentik-jwt"
            "X-authentik-meta-jwks"
            "X-authentik-meta-outpost"
            "X-authentik-meta-provider"
            "X-authentik-meta-app"
            "X-authentik-meta-version"
          ];
          trustForwardHeader = true;
        };
      };
    };
}
