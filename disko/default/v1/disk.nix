{
  device,
  withDocker ? false,
  withSwap ? true,
  swapSize ? "1G",
  ...
}:

let
  baseSubvolumes = {
    "/home_root" = {
      mountpoint = "/root";
      mountOptions = [
        "compress=zstd"
        "noatime"
      ];
    };
    "/home" = {
      mountpoint = "/home";
      mountOptions = [
        "compress=zstd"
        "noatime"
      ];
    };
    "/nix" = {
      mountpoint = "/nix";
      mountOptions = [
        "compress=zstd"
        "noatime"
      ];
    };
    "/root" = {
      mountpoint = "/";
      mountOptions = [
        "compress=zstd"
        "noatime"
      ];
    };
    "/etc-ssh" = {
      mountpoint = "/etc/ssh";
      mountOptions = [
        "compress=zstd"
        "noatime"
      ];
    };
    "/persistent" = {
      mountpoint = "/persistent";
      mountOptions = [
        "compress=zstd"
        "noatime"
      ];
    };
  };

  dockerSubvolumes = {
    "/@docker" = {
      mountpoint = "/docker";
      mountOptions = [
        "compress=zstd"
        "noatime"
      ];
    };

    "/var-lib-docker" = {
      mountpoint = "/var/lib/docker";
      mountOptions = [
        "compress=zstd"
        "noatime"
      ];
    };
  };

  subvolumes = if withDocker then baseSubvolumes // dockerSubvolumes else baseSubvolumes;
in
{

  fileSystems."/etc/ssh".neededForBoot = true;
  fileSystems."/persistent".neededForBoot = true;

  # Hybrid bootloader setup for BIOS and UEFI systems
  boot = {
    loader = {
      grub = {
        enable = true;
        efiSupport = true;
        efiInstallAsRemovable = true;
      };
    };
  };

  disko.devices.disk.vda = {
    inherit device;
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        bios = {
          type = "EF02";
          size = "1M";
        };
        ESP = {
          type = "EF00";
          size = "2G";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
      }
      // (
        if withSwap then
          {
            swap = {
              size = swapSize;
              content = {
                type = "swap";
              };
            };
          }
        else
          { }
      )
      // {
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            inherit subvolumes;
          };
        };
      };
    };
  };
}
