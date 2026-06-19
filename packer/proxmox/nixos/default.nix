{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  builders = [
    (
      (import ../connection-header.nix)
      // (lib.mkProxmoxIsoBuilder {
        inherit inputs;
        storage_pool = "fast";
        vm_id = "10002";
        vm_hostname = "nixos";
        disk_size = "10G";
        cores = 6;
        memoryGiB = 4;
        iso_file = "{{user `nixos_iso_file`}}";
        useSerialInsteadOfVga = true;
        bootwaitTime = "30s";
      })
    )
  ];

  provisioners = [
    {
      type = "shell";
      inline = [
        #!/usr/bin/env bash
        # Liefert die lokal genutzte Quell-IP für eine Route ins Internet
        "ip -4 route get 1.1.1.1 | awk '{print $7}' > /tmp/ip-vm-nixos"
      ];

    }
    {
      type = "file";
      direction = "download";
      source = "/tmp/ip-vm-nixos";
      destination = "./ip-vm-nixos";
    }
    {
      type = "shell-local";
      script = ./run-nixosanywhere.sh;
    }
  ];

  post-processors = [
    (lib.mkProxmoxPostprocessor {
      inherit pkgs;
      vm_id = "10002";
    })
  ];
}
