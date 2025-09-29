{ lib, config, options, ... }:
with lib;
let
  cfg = config.lh.services.copyparty;
  externalCacheDir = "/var/cache/copyparty";
in
{
  options.lh.services.copyparty = {
    enable = lib.mkEnableOption "Leon's Opinionated Copyparty";

    traefikIntegration = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = config.lh.services.traefik.enable;
        description = "Whether to integrate Copyparty with Traefik";
      };
      certResolver = lib.mkOption {
        type = lib.types.str;
        default =
          if config.lh.services.copyparty.traefikIntegration.enable then
            throw "You must set a certResolver if traefikIntegration is enabled"
          else
            "";
        description =
          "The certResolver to use for the Copyparty Traefik router";
        example = "le";
      };
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "copyparty.${
          config.networking.fqdn or "${config.networking.hostName}.local"
        }";
      defaultText = lib.literalExpression ''
        "copyparty.''${config.networking.fqdn or "''${config.networking.hostName}.local"}"
      '';
      description = "The domain to access Copyparty at";
      example = "copyparty.example.com";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/copyparty";
      description = "Path where copyparty data will be stored";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      description = ''
        Global settings to apply.
        Directly maps to values in the [global] section of the copyparty config.
        Cannot set "c" or "hist", those are set by this module.
      '';
      default = {
        no-reload = true;
        hist = externalCacheDir;
      };
      example = literalExpression ''
        {
          i = "0.0.0.0";
          p = [ 3210 3211 ];
          no-reload = true;
          hist = "/var/cache/copyparty";
        }
      '';
    };

    globalExtraConfig = mkOption {
      type = types.str;
      default = "";
      description =
        "Appended to the end of the [global] section verbatim. This is useful for flags which are used in a repeating manner (e.g. ipu: 255.255.255.1=user) which can't be repeated in the settings = {} attribute set.";
    };

    accounts = mkOption {
      type = types.attrsOf (types.submodule (_: {
        options = {
          passwordFile = mkOption {
            type = types.str;
            description = ''
              Runtime file path to a file containing the user password.
              Must be readable by the copyparty user.
            '';
            example = "/run/keys/copyparty/ed";
          };
        };
      }));
      description = ''
        A set of copyparty accounts to create.
      '';
      default = { };
      example = literalExpression ''
        {
          ed.passwordFile = "/run/keys/copyparty/ed";
        };
      '';
    };

    volumes = mkOption {
      type = types.attrsOf (types.submodule (_: {
        options = {
          path = mkOption {
            type = types.path;
            description = ''
              Path of a directory to share.
            '';
          };
          access = mkOption {
            type = types.attrs;
            description = ''
              Attribute list of permissions and the users to apply them to.

              The key must be a string containing any combination of allowed permission:
                "r" (read):   list folder contents, download files
                "w" (write):  upload files; need "r" to see the uploads
                "m" (move):   move files and folders; need "w" at destination
                "d" (delete): permanently delete files and folders
                "g" (get):    download files, but cannot see folder contents
                "G" (upget):  "get", but can see filekeys of their own uploads
                "h" (html):   "get", but folders return their index.html
                "a" (admin):  can see uploader IPs, config-reload

              For example: "rwmd"

              The value must be one of:
                an account name, defined in `accounts`
                a list of account names
                "*", which means "any account"
            '';
            example = literalExpression ''
              {
                # wG = write-upget = see your own uploads only
                wG = "*";
                # read-write-modify-delete for users "ed" and "k"
                rwmd = ["ed" "k"];
              };
            '';
            default = { };
          };
          flags = mkOption {
            type = types.attrs;
            description = ''
              Attribute list of volume flags to apply.
              See `copyparty --help-flags` for more details.
            '';
            example = literalExpression ''
              {
                # "fk" enables filekeys (necessary for upget permission) (4 chars long)
                fk = 4;
                # scan for new files every 60sec
                scan = 60;
                # volflag "e2d" enables the uploads database
                e2d = true;
                # "d2t" disables multimedia parsers (in case the uploads are malicious)
                d2t = true;
                # skips hashing file contents if path matches *.iso
                nohash = "\.iso$";
              };
            '';
            default = { };
          };
        };
      }));
      description = ''
        A set of copyparty volumes to create.
      '';
      default = {
        "/" = {
          path = cfg.dataPath;
          access = { r = "*"; };
          flags = {
            fk = 4;
            scan = 60;
            e2d = true;
            d2t = true;
          };
        };
      };
      example = literalExpression ''
        {
          "/" = {
            path = "/srv/copyparty";
            access = {
              r = "*";
              rw = [ "ed" "k" ];
            };
            flags = {
              fk = 4;
              scan = 60;
              e2d = true;
              d2t = true;
              nohash = "\.iso$";
            };
          };
        }
      '';
    };
  };

  # Build persistence definition only if impermanence (environment.persistence option) exists.
  config =
    let
      haveImpermanence = options ? environment && options.environment
        ? persistence;
      persistenceDef =
        if haveImpermanence then {
          environment.persistence."/persistent".directories = [
            {
              directory = cfg.dataPath;
              user = "copyparty";
              group = "copyparty";
              mode = "0755";
            }
            {
              directory = externalCacheDir;
              user = "copyparty";
              group = "copyparty";
              mode = "0755";
            }
          ];
        } else
          { };
    in
    lib.mkIf cfg.enable (persistenceDef // {
      services.copyparty = {
        enable = true;
        openFilesLimit = 8192;
        inherit (cfg) accounts volumes;

        settings = cfg.settings // (if cfg.traefikIntegration.enable then {
          i = "unix:770:copyparty:/run/copyparty-socket/copyparty.sock";
          rproxy = 1;
          xff-hdr = "X-Forwarded-For";
        } else
          { });
        inherit (cfg) globalExtraConfig;
      };

      # Traefik integration
      lh.services.traefik.dynamicConfig = lib.mkIf cfg.traefikIntegration.enable {
        http.routers.copyparty = {
          rule = "Host(`${cfg.domain}`)";
          entryPoints = [ "websecure" ];
          service = "copyparty";
          tls = { inherit (cfg.traefikIntegration) certResolver; };
        };
        http.services.copyparty.loadBalancer.servers =
          [{ url = "unix+http:/run/copyparty-socket/copyparty.sock"; }];
      };

      # Allow Traefik to access the copyparty socket
      users.users.traefik =
        lib.mkIf cfg.traefikIntegration.enable { extraGroups = [ "copyparty" ]; };
      systemd = {
        services.copyparty = {
          serviceConfig = {
            BindPaths = [ "/run/copyparty-socket" ];
            ReadWritePaths = [ "/run/copyparty-socket" ];
          };
        };

        # Make Traefik depend on copyparty service
        services.traefik = lib.mkIf cfg.traefikIntegration.enable {
          after = [ "copyparty.service" ];
          wants = [ "copyparty.service" ];
          serviceConfig = { BindReadOnlyPaths = [ "/run/copyparty-socket" ]; };
        };

        # Create data directory
        tmpfiles.rules = [
          "d ${cfg.dataPath} 0755 copyparty copyparty - -"
          "d ${externalCacheDir} 0755 copyparty copyparty - -"
          "d /run/copyparty-socket 0755 copyparty copyparty - -"
        ];
      };
    });
}
