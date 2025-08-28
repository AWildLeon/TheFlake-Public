{ config, lib, ... }:

{
  boot.initrd.postResumeCommands = lib.mkAfter ''
    mkdir /btrfs_tmp
    mount "${config.fileSystems."/".device}" /btrfs_tmp

    # Function to delete subvolume recursively
    delete_subvolume_recursively() {
        IFS=$'\n'
        for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
            delete_subvolume_recursively "/btrfs_tmp/$i"
        done
        btrfs subvolume delete "$1"
    }
    delete_subvolume_recursively /btrfs_tmp/root

    btrfs subvolume create /btrfs_tmp/root

    umount /btrfs_tmp
  '';

  fileSystems."/persistent".neededForBoot = true;

  fileSystems."/etc/ssh".neededForBoot = lib.mkIf (config.fileSystems ? "/etc/ssh") true;

  environment.persistence."/persistent" = {
    directories = [
      "/var/lib/nixos"
      "/var/log"
      "/var/lib/cloud/"
      "/var/lib/systemd/journal"
      "/var/lib/systemd/coredump"

      "/etc/NetworkManager/system-connections"
      "/var/lib/NetworkManager"

    ];
    files = [
      "/etc/machine-id"
    ];
  };
}
