{ lib, config, options, pkgs, ... }: {

  options.lh.services.glance = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable Glance (https://github.com/glanceapp/glance).
      '';
    };

    enableGlanceIcalEvents = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to enable the Glance iCal Events plugin";
    };

    settings = lib.mkOption {
      inherit ((pkgs.formats.yaml { })) type;
      default = { };
      description = "Extra settings to pass to glance's configuration file";
    };

    assets-path = lib.mkOption {
      type = lib.types.str;
      default = "";
      description =
        "Path to the glance assets, if you want to override the default";
      example = "/path/to/glance/assets";
    };

    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description =
        "A list of environment files to include in the glance service";
    };

    traefikIntegration = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = config.lh.services.traefik.enable;
        description = "Whether to integrate glance with Traefik";
      };

      certResolver = lib.mkOption {
        type = lib.types.str;
        default =
          if config.lh.services.glance.traefikIntegration.enable then
            throw "You must set a certResolver if traefikIntegration is enabled"
          else
            "";
        description = "The certResolver to use for the glance Traefik router";
        example = "le";
      };
      middlewares = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description =
          "A list of middlewares to apply to the glance Traefik router";
      };
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "glance.${
          config.networking.fqdn or "${config.networking.hostName}.local"
        }";
      defaultText = lib.literalExpression ''
        "glance.''${config.networking.fqdn or "''${config.networking.hostName}.local"}"
      '';
      description = "The domain to access glance at";
      example = "glance.example.com";
    };
  };

  config = lib.mkIf config.lh.services.glance.enable {
    assertions = [{
      assertion = !(config.lh.services.glance.settings ? server);
      message =
        "config.lh.services.glance.settings.server is managed internally by this module. Please use the provided options like 'assets-path' instead of setting server configuration directly.";
    }];

    services.glance = {
      enable = true;
      package = pkgs.glance.overrideAttrs (oldAttrs: {
        patches = (oldAttrs.patches or [ ]) ++ [
          # Add socket support for the web UI, These are not exactly the git repo commit patches, these have disabled some checks.
          ./patches/glanceapp/sockets.patch
          ./patches/glanceapp/sockets-mode.patch
        ];
      });

      openFirewall = false;

      settings = {
        server = {
          assets-path =
            if (config.lh.services.glance.assets-path != "") then
              config.lh.services.glance.assets-path
            else
              "/var/lib/glance/assets";
          socket-path = "/run/glance/webui.sock";
          socket-mode = "0660";
          proxied = true;
        };
      } // config.lh.services.glance.settings;
    };

    lh.services.traefik.dynamicConfig =
      lib.mkIf config.lh.services.glance.traefikIntegration.enable {
        http.routers.glance = {
          rule = "Host(`${config.lh.services.glance.domain}`)";
          entryPoints = [ "websecure" ];
          service = "glance";

          tls = {
            inherit (config.lh.services.glance.traefikIntegration) certResolver;

            domains = [{
              main = "onlh.de";
              sans = [ "*.onlh.de" ];
            }];
          };

          middlewares = [ "securityheaders" ]
            ++ config.lh.services.glance.traefikIntegration.middlewares;
        };
        http.services.glance.loadBalancer.servers =
          [{ url = "unix+http:/run/glance/webui.sock"; }];
      };

    systemd = {
      services.traefik =
        lib.mkIf config.lh.services.glance.traefikIntegration.enable {
          requires = [ "glance.service" ];
          after = [ "glance.service" ];
          serviceConfig = { BindReadOnlyPaths = [ "/run/glance/webui.sock" ]; };
        };

      services.glance.serviceConfig = {
        User = "glance";
        Group = "glance";

        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
        PrivateDevices = true;
        ProtectSystem = "strict";

        EnvironmentFile =
          lib.mkIf (config.lh.services.glance.environmentFiles != [ ])
            config.lh.services.glance.environmentFiles;

        SystemCallFilter = [
          "~@privileged"
          "~@setuid"
          "~@reboot"
          "~@module"
          "~@raw-io"
          "~@mount"
          "~@swap"
          "~@clock"
          "~@debug"
          "~@cpu-emulation"
          "~@obsolete"
          "~@resources"
        ];
        SystemCallErrorNumber = "EPERM";

        ProtectProc = "invisible";
        PrivateIPC = true;
        KeyringMode = "private";
        PrivateUsers = true;
        MemoryDenyWriteExecute = true;
        ProtectClock = true;

        CapabilityBoundingSet = lib.mkOverride 0 [ "" ];
        AmbientCapabilities = lib.mkOverride 0 [ "" ];

        ProcSubset = lib.mkForce "pid";

        SecureBits = "noroot-locked";
        RestrictSUIDSGID = true;

        RootDirectory = "/run/jails/glance";

        BindReadOnlyPaths = [
          "/nix/store"
          "/etc/ssl"
          "/etc/resolv.conf"
          "/etc/hosts"
          "/run/current-system/sw/bin"
          "/run/wrappers/bin"
          "/etc/static/ssl"
          "/etc/passwd"
        ];
        BindPaths =
          [ "/var/lib/glance:/var/lib/glance" "/run/glance:/run/glance" ];

        ReadWritePaths = [ "/var/lib/glance" "/run/glance" ];
        ReadOnlyPaths = [ "/nix/store" ];

      };

      tmpfiles.rules = config.lh.lib.mkJailTmpfiles
        {
          serviceName = "glance";
          user = "glance";
          group = "glance";
        } ++ (if config.lh.services.glance.enableGlanceIcalEvents then
        config.lh.lib.mkJailTmpfiles
          {
            serviceName = "glance-ical-events";
            user = "glance-ical-events";
            group = "glance-ical-events";
          }
      else
        [ ]);
    };

    users = {
      users.traefik =
        lib.mkIf config.lh.services.glance.traefikIntegration.enable {
          extraGroups = [ "glance" ];
        };

      groups.glance = { };
      users.glance = {
        isSystemUser = true;
        group = "glance";
        home = "/var/lib/glance";
        createHome = false;
        description = "Glance User";
      };
    };

    services.glance-ical-events =
      lib.mkIf config.lh.services.glance.enableGlanceIcalEvents {
        enable = true;
        host = "127.80.76.90";
        port = 8076;
        workers = 1;
      };

    systemd.services."glance-ical-events".serviceConfig =
      lib.mkIf config.lh.services.glance.enableGlanceIcalEvents {
        RootDirectory = "/run/jails/glance-ical-events";
        BindReadOnlyPaths = [
          "/nix/store"
          "/etc/ssl"
          "/etc/resolv.conf"
          "/etc/hosts"
          "/run/current-system/sw/bin"
          "/run/wrappers/bin"
          "/etc/static/ssl"
          "/etc/passwd"
        ];

        ReadOnlyPaths = [ "/nix/store" ];

      };

  };
}
