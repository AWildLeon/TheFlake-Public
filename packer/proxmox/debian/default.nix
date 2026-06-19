{
  lib,
  inputs,
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
        vm_id = "10001";
        vm_hostname = "debian";
        disk_size = "10G";
        cores = 6;
        memoryGiB = 4;
        iso_file = "{{user `debian_iso_file`}}";
        useSerialInsteadOfVga = false;
        bootwaitTime = "20s";
      })
      // {
        boot_command = [
          "c"
          "<wait>"
          "linux /install.amd/vmlinuz auto-install/enable=true debconf/priority=critical preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg<enter><wait>"
          "initrd /install.amd/initrd.gz<enter><wait>"
          "boot<enter><wait>"
        ];

        http_directory = ./http;
        # (Optional) Bind IP Address and Port
        # http_bind_address = "0.0.0.0"
        http_port_min = 10001;
        http_port_max = 10001;
      }
    )
  ];

  provisioners = [
    {
      type = "ansible";
      playbook_file = ./ansible/playbook.yml;
    }
  ];

  post-processors = [
    (lib.mkProxmoxPostprocessor {
      inherit pkgs;
      vm_id = "10001";
    })
  ];
}
