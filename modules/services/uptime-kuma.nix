{ lib, config, options, ... }:
let cfg = config.lh.services.uptime-kuma;
in {
  options.lh.services.uptime-kuma = {
    enable = lib.mkEnableOption "uptime-kuma server";
    domain = lib.mkOption {
      type = lib.types.str;
      default = "uptime-kuma.${
          config.networking.fqdn or "${config.networking.hostName}.local"
        }";
      defaultText = lib.literalExpression ''
        "uptime-kuma.''${config.networking.fqdn or "''${config.networking.hostName}.local"}"
      '';
      description = "The domain to access uptime-kuma at";
      example = "uptime-kuma.example.com";
    };
    traefikIntegration = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = config.lh.services.traefik.enable;
        description = "Whether to integrate uptime-kuma with Traefik";
      };
      certResolver = lib.mkOption {
        type = lib.types.str;
        default =
          if config.lh.services.uptime-kuma.traefikIntegration.enable then
            throw "You must set a certResolver if traefikIntegration is enabled"
          else
            "";
        description =
          "The certResolver to use for the uptime-kuma Traefik router";
        example = "le";
      };

      middlewares = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description =
          "A list of middlewares to apply to the uptime-kuma Traefik router";
      };
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = cfg.traefikIntegration.enable
        -> cfg.traefikIntegration.certResolver != "";
      message =
        "certResolver must be set when traefik integration is enabled for uptime-kuma";
    }];

    services.uptime-kuma = {
      enable = true;
      # TODO: Maybe Enable.
      #   # Use custom package with beta version
      #   package = pkgs.buildNpmPackage {
      #     pname = "uptime-kuma";
      #     version = "2.0.0-beta.4";

      #     src = pkgs.fetchFromGitHub {
      #       owner = "louislam";
      #       repo = "Uptime-Kuma";
      #       rev = "2.0.0-beta.4";
      #       hash = "sha256-cgKyqxS+SsTqhWz9tF6K7bYSCugbEiSHIFKAh/bV01M=";
      #     };

      #     npmDepsHash = "sha256-oQaDRmCY9xtMF1jGiOMQYXiTTpbHJymro7vBLtPw1iU=";
      #   };
      settings = {
        HOST = "127.23.12.7";
        PORT = "38412";
      };
    };

    lh.services.traefik.dynamicConfig = lib.mkIf cfg.traefikIntegration.enable {
      http.routers.uptime-kuma = {
        rule = "Host(`${cfg.domain}`)";
        entryPoints = [ "websecure" ];
        service = "uptime-kuma";
        middlewares = [ "securityheaders" ]
          ++ cfg.traefikIntegration.middlewares;
        tls = { inherit (cfg.traefikIntegration) certResolver; };
      };
      http.services.uptime-kuma.loadBalancer.servers =
        [{ url = "http://127.23.12.7:38412"; }];
    };

    systemd.services.uptime-kuma = {
      serviceConfig = {
        ReadWritePaths =
          [ "/var/lib/uptime-kuma" "/var/lib/private/uptime-kuma" ];
        ProtectSystem = lib.mkForce "strict";
        BindReadOnlyPaths = [
          "/etc/passwd"
          "/nix/store"
          "/etc/ssl"
          "/etc/resolv.conf"
          "/etc/hosts"
          "/run/current-system/sw/bin"
          "/run/wrappers/bin"
          "/etc/static/ssl"
          "/bin"
          "/usr/bin"
        ];

        BindPaths = [ "/var/lib/uptime-kuma" "/var/lib/private/uptime-kuma" ];
        MountAPIVFS = true;

        user = "uptime-kuma";
        group = "uptime-kuma";
        ProtectProc = lib.mkForce "invisible";
        ProcSubset = "pid";
        UMask = lib.mkForce "0077";

        PrivateUsers = true;

        SystemCallFilter = [
          "~@cpu-emulation"
          "~@debug"
          "~@mount"
          "~@obsolete"
          "~@swap"
          "~@clock"
          "~@reboot"
          "~@module"
          "~@resources"
        ];

        # AmbientCapabilities = lib.mkForce "CAP_NET_RAW";
        # CapabilityBoundingSet = lib.mkForce "CAP_NET_RAW";

        RootDirectory = "/run/jails/uptime-kuma";
        RootDirectoryStartOnly = true;
      };
    };

    users.users.uptime-kuma = {
      isSystemUser = true;
      group = "uptime-kuma";
      description = "Uptime-Kuma user";
      home = "/var/lib/private/uptime-kuma";
    };

    users.groups.uptime-kuma = { };

    systemd.tmpfiles.rules = config.lh.lib.mkJailTmpfiles {
      serviceName = "uptime-kuma";
      user = "uptime-kuma";
      group = "uptime-kuma";
      dataPaths = [ "/var/lib/uptime-kuma" "/var/lib/private/uptime-kuma" ];
    };

    # Persistence
    # Is already handled by /var/lib/private in impermanence
  };
}
