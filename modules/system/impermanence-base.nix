{ config, lib, options, ... }:

let
  cfg = config.lh.system.impermanence;
  # Check if impermanence is available by looking for the environment.persistence option
  hasImpermanence = builtins.hasAttr "environment" options && builtins.hasAttr "persistence" options.environment;
in
{
  options.lh.system.impermanence = {
    enable = lib.mkEnableOption "Enable impermanence configuration with btrfs subvolume management";

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
        "/etc/NetworkManager/system-connections"
        "/var/lib/NetworkManager"
        { directory = "/var/lib/private/"; mode = "0700"; }
      ];

      lh.system.impermanence.persistentFiles = [
        "/etc/machine-id"
      ];

      # Btrfs subvolume recreation on boot
      boot.initrd.postResumeCommands = lib.mkAfter (
        let
          devicePath = if cfg.rootDevice != "" then cfg.rootDevice else "${config.fileSystems."/".device}";
        in
        ''
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
          delete_subvolume_recursively /btrfs_tmp/${cfg.rootSubvolume}

          btrfs subvolume create /btrfs_tmp/${cfg.rootSubvolume}

          umount /btrfs_tmp
        ''
      );

      # Persistent filesystem configuration
      fileSystems."${cfg.persistentPath}".neededForBoot = true;

      # SSH persistence
      fileSystems."/etc/ssh".neededForBoot = lib.mkIf (config.fileSystems ? "/etc/ssh") true;
    })

    # Persistence configuration (only when impermanence module is available)
    (lib.mkIf (cfg.enable && cfg.enablePersistence) (lib.optionalAttrs hasImpermanence {
      environment.persistence."${cfg.persistentPath}" = {
        directories = cfg.persistentDirectories;
        files = cfg.persistentFiles;
      };
    }))
  ];
}
