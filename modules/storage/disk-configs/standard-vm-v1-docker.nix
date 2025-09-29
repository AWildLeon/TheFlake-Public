# Copyright (c) 2025 Leon Hubrich
# All rights reserved. See LICENSE for details.
#
# Standard VM disk configuration - Version 1.0
# Features:
# - GPT partitioning with BIOS compatibility
# - 2GB EFI System Partition
# - 1GB swap partition
# - BTRFS root with subvolumes for impermanence
# - zstd compression with noatime for performance

{ ... }:
{
  imports = [ ./standard-vm-v1.nix ];

  disko.devices = {
    disk = {
      vda = {
        content = {
          partitions = {
            root = {
              content = {
                subvolumes = {
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
              };
            };
          };
        };
      };
    };
  };

}
