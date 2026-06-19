{ config, lib, ... }:
let
  cfg = config.lh.services.monero;
in
{

  options.lh.services.monero = {
    enable = lib.mkEnableOption "Monero node";
    extraConfig = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Extra configuration to be added to monerod";
    };
    overrides = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Overrides for the monero module";
    };
  };

  config = lib.mkIf cfg.enable {
    services.monero = {
      enable = true;
      dataDir = "/var/lib/monero";
      banlist = ./ban_list.txt;
      prune = true;
      inherit (cfg) extraConfig;
    }
    // cfg.overrides;

    systemd = {
      services.monero = {
        serviceConfig = {
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = lib.mkForce "strict";
          ReadOnlyPaths = [ "/etc" ];
          ReadWritePaths = [ "/var/lib/monero" ];
          BindReadOnlyPaths = [
            "/nix/store"
            "/etc/ssl"
            "/etc/resolv.conf"
            "/etc/hosts"
            "/run/current-system/sw/bin"
            "/run/wrappers/bin"
            "/etc/static/ssl"
          ];
          BindPaths = [ "/var/lib/monero" ];
          MountAPIVFS = true;
          ProtectProc = lib.mkForce "invisible";
          ProcSubset = "pid";
          UMask = lib.mkForce "0077";
          RootDirectory = "/run/jails/monero";
          CapabilityBoundingSet = "";
          AmbientCapabilities = "";
          RestrictNamespaces = "yes";
          PrivateUsers = true;
          SystemCallFilter = [
            "~@clock"
            "~@cpu-emulation"
            "~@debug"
            "~@mount"
            "~@obsolete"
            "~@privileged"
            "~@raw-io"
            "~@reboot"
            "~@swap"
          ];
          PrivateDevices = true;
          ProtectClock = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectKernelModules = true;
          ProtectHostname = true;
          RestrictRealtime = true;
          ProtectKernelTunables = true;
          LockPersonality = true;
        };
      };

      tmpfiles.rules = config.lh.lib.mkJailTmpfiles {
        serviceName = "monero";
        user = "monero";
        group = "monero";
      };
    };

    lh.system.impermanence.persistentDirectories = [
      {
        directory = "/var/lib/monero";
        user = "monero";
        group = "monero";
      }
    ];
  };

}
