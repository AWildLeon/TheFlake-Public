{ pkgsUnstable, lib, config, ... }:

let cfg = config.lh.services.nameserver;

in {
  imports = [ ];

  options.lh.services.nameserver = {
    fqdn = lib.mkOption {
      type = lib.types.str;
      default = config.networking.fqdn or "${config.networking.hostName}.local";
      defaultText = lib.literalExpression ''
        config.networking.fqdn or "''${config.networking.hostName}.local"
      '';
      description = "The FQDN for the nameserver web interface";
      example = "dns.example.com";
    };
    enable = lib.mkEnableOption "Technitium DNS Server";

    traefikIntegration = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = config.lh.services.traefik.enable;
        description = "Whether to integrate nameserver with Traefik";
      };

      certResolver = lib.mkOption {
        type = lib.types.str;
        default =
          if config.lh.services.nameserver.traefikIntegration.enable then
            throw "You must set a certResolver if traefikIntegration is enabled"
          else
            "";
        description =
          "The certResolver to use for the nameserver Traefik router";
        example = "le";
      };

      middlewares = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description =
          "A list of middlewares to apply to the nameserver Traefik router";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = cfg.traefikIntegration.enable
        -> cfg.traefikIntegration.certResolver != "";
      message =
        "certResolver must be set when traefik integration is enabled for nameserver";
    }];

    services.technitium-dns-server = {
      enable = true;
      openFirewall = true;
      package = pkgsUnstable.technitium-dns-server;
    };

    # Create user and group for the service
    users.users.technitium-dns-server = {
      group = "technitium-dns-server";
      isSystemUser = true;
      home = "/var/lib/nameserver";
      createHome = false; # StateDirectory will handle this
    };

    users.groups.technitium-dns-server = { };

    # Traefik integration
    lh.services.traefik.dynamicConfig = lib.mkIf cfg.traefikIntegration.enable {
      http.routers.nameserver = {
        rule = "Host(`${cfg.fqdn}`)";
        entryPoints = [ "websecure" ];
        service = "nameserver";
        middlewares = [ "securityheaders" ]
          ++ cfg.traefikIntegration.middlewares;
        tls = { inherit (cfg.traefikIntegration) certResolver; };
      };
      http.services.nameserver.loadBalancer.servers =
        [{ url = "http://127.0.0.1:5380"; }];
    };

    # systemd-Overrides für die Unit
    systemd.services.technitium-dns-server.serviceConfig = {
      # Use /var/lib/nameserver instead of the default technitium-dns-server
      StateDirectory = lib.mkForce "nameserver";
      WorkingDirectory = lib.mkForce "/var/lib/nameserver";
      ExecStart = lib.mkForce
        "${pkgsUnstable.technitium-dns-server}/bin/technitium-dns-server /var/lib/nameserver";
      # Disable DynamicUser to avoid conflicts with existing directory
      DynamicUser = lib.mkForce false;
      # Set a specific user instead
      User = "technitium-dns-server";
      Group = "technitium-dns-server";

      BindPaths = lib.mkForce [ ];
    };

    # Persistenz via impermanence
    environment = lib.optionalAttrs
      (builtins.hasAttr "environment" config
        && builtins.hasAttr "persistence" config.environment)
      {
        persistence."/persistent" = {
          directories = [ "/var/lib/nameserver" ];
        };
      };
  };
}
