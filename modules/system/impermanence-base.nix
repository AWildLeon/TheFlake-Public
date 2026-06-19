{
  config,
  lib,
  pkgs,
  options,
  utils,
  ...
}:

let
  cfg = config.lh.system.impermanence;
  # Check if impermanence is available by looking for the environment.persistence option
  hasImpermanence =
    builtins.hasAttr "environment" options && builtins.hasAttr "persistence" options.environment;

  devicePath = if cfg.rootDevice != "" then cfg.rootDevice else "${config.fileSystems."/".device}";
in
{
  options.lh.system.impermanence = {
    enable = lib.mkEnableOption "Enable impermanence configuration with btrfs subvolume management";
    removeHome = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Remove /home directory from persistence (useful for stateless setups)";
    };

    persistentPath = lib.mkOption {
      type = lib.types.str;
      default = "/persistent";
      description = "Path to the persistent storage mount point";
    };

    rootSubvolume = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "Name of the root subvolume to recreate on boot";
    };

    homeSubvolume = lib.mkOption {
      type = lib.types.str;
      default = "home";
      description = "Name of the home subvolume to recreate on boot (if removeHome is false)";
    };

    rootDevice = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Root filesystem device path (auto-detected if empty)";
    };

    persistentDirectories = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.str lib.types.attrs);
      default = [ ];
      description = "Directories to persist across reboots";
      apply = lib.lists.unique;
    };

    persistentFiles = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.str lib.types.attrs);
      default = [ ];
      description = "Files to persist across reboots";
    };

    enablePersistence = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable environment.persistence configuration (requires impermanence module)";
    };
  };

  config = lib.mkMerge [
    # Base impermanence configuration (btrfs cleanup)
    (lib.mkIf cfg.enable {
      # Set default persistent directories
      lh.system.impermanence.persistentDirectories = [
        "/var/lib/nixos"
        "/var/log"
        "/var/lib/cloud/"
        "/var/lib/systemd/journal"
        "/var/lib/systemd/coredump"
        "/var/lib/NetworkManager"
        {
          directory = "/etc/NetworkManager/system-connections";
          mode = "0700";
        }

        {
          directory = "/var/lib/private/";
          mode = "0700";
        }
      ]
      ++ lib.optionals config.security.acme.acceptTerms [
        {
          directory = "/var/lib/acme/";
          mode = "0755";
          user = "acme";
          group = "acme";
        }
      ];

      lh.system.impermanence.persistentFiles = [ "/etc/machine-id" ];

      # Btrfs subvolume recreation on boot, run as an early systemd-stage1
      # service before the real root is mounted. On failure we drop into the
      # initrd emergency shell rather than booting on a half-wiped root.
      boot.initrd.systemd.emergencyAccess = lib.mkDefault true;

      # The rollback service runs with a restricted PATH; these must actually be
      # present in the initrd. util-linuxMinimal (mount) is already pulled in by
      # systemd; btrfs-progs and coreutils are not, so include them explicitly.
      boot.initrd.systemd.initrdBin = with pkgs; [
        btrfs-progs
        coreutils
      ];

      boot.initrd.systemd.services.rollback = {
        description = "Rollback btrfs root to a pristine state";
        wantedBy = [ "initrd.target" ];
        after = [
          "local-fs-pre.target"
          "${utils.escapeSystemdPath devicePath}.device"
        ];
        before = [ "sysroot.mount" ];
        # NOTE: util-linuxMinimal, not util-linux. The full package splits `mount`
        # into a separate output that is not present in the systemd initrd.
        path = with pkgs; [
          btrfs-progs
          coreutils
          util-linuxMinimal
        ];
        unitConfig = {
          DefaultDependencies = "no";
          OnFailure = "emergency.target";
          OnFailureJobMode = "replace-irreversibly";
        };
        serviceConfig.Type = "oneshot";
        script = ''
          set -euo pipefail
          mkdir /btrfs_tmp
          mount "${devicePath}" /btrfs_tmp

          # Function to delete subvolume recursively
          delete_subvolume_recursively() {
              IFS=$'\n'
              for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
                  delete_subvolume_recursively "/btrfs_tmp/$i"
              done
              btrfs subvolume delete "$1"
          }
          echo "Deleting old root subvolume"
          delete_subvolume_recursively /btrfs_tmp/${cfg.rootSubvolume}
        ''
        + lib.optionalString cfg.removeHome ''
          echo "Recreating home subvolume"
          delete_subvolume_recursively /btrfs_tmp/${cfg.homeSubvolume}_previous || true
          mv /btrfs_tmp/${cfg.homeSubvolume} /btrfs_tmp/${cfg.homeSubvolume}_previous
          btrfs subvolume create /btrfs_tmp/${cfg.homeSubvolume}

          # Recreate home subfolder for each user with proper permissions
          ${lib.concatMapStrings
            (u: ''
              mkdir -p /btrfs_tmp/${cfg.homeSubvolume}/${lib.removePrefix "/home/" u.home}
              chown ${toString u.uid}:${
                toString config.users.groups.${u.group}.gid
              } /btrfs_tmp/${cfg.homeSubvolume}/${lib.removePrefix "/home/" u.home}
              chmod ${u.homeMode} /btrfs_tmp/${cfg.homeSubvolume}/${lib.removePrefix "/home/" u.home}
            '')
            (
              lib.filter (u: u.createHome && lib.hasPrefix "/home/" u.home && u.uid != null) (
                lib.attrValues config.users.users
              )
            )
          }
        ''
        + ''
          echo "Recreating root subvolume"
          btrfs subvolume create /btrfs_tmp/${cfg.rootSubvolume}

          umount /btrfs_tmp
        '';
      };

      # Persistent filesystem configuration
      fileSystems."${cfg.persistentPath}".neededForBoot = true;
    })

    # Persistence configuration (only when impermanence module is available)
    (lib.mkIf (cfg.enable && cfg.enablePersistence) (
      lib.optionalAttrs hasImpermanence {
        environment.persistence."${cfg.persistentPath}" = {
          hideMounts = true;
          directories = cfg.persistentDirectories;
          files = cfg.persistentFiles;
        };
      }
    ))
  ];
}
