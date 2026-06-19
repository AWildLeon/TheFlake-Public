{
  storage_pool ? "fast",
  vm_id,
  vm_hostname,
  inputs,
  disk_size ? "10G",
  cores ? 6,
  memoryGiB ? 4,
  iso_file,
  useSerialInsteadOfVga ? true,
  bootwaitTime ? "30s",
  ...
}:
let
  vgaConfig =
    if useSerialInsteadOfVga then
      {
        type = "serial0";
      }
    else
      {
        type = "std";
      };
  memoryMiB = toString (memoryGiB * 1024);
in
{

  name = vm_hostname;

  inherit vm_id;
  vm_name = vm_hostname;
  template_description = "This VM is using the ${vm_hostname} template generated on {{ isotime \"02 Jan 2006\" }}\n\nBuild using Flake Revision: ${
    inputs.self.shortRev or inputs.self.dirtyShortRev or "unknown"
  }";
  type = "proxmox-iso";

  rng0 = {
    source = "/dev/urandom";
    max_bytes = 1024;
    period = 1000;
  };

  disks = {
    inherit disk_size storage_pool;
    discard = true;
    io_thread = true;
    type = "virtio";
  };

  qemu_agent = true;
  scsi_controller = "virtio-scsi-single";

  network_adapters = {
    model = "virtio";
    bridge = "Infra";
    firewall = "false";
  };

  ssh_username = "root";

  ssh_timeout = "20m";
  os = "l26";
  machine = "q35";
  cpu_type = "host";

  bios = "ovmf";
  efi_config = {
    efi_storage_pool = storage_pool;
    pre_enrolled_keys = false;
  };

  cloud_init = true;
  cloud_init_storage_pool = storage_pool;

  boot = "order=virtio0;scsi0";
  boot_wait = bootwaitTime;

  vga = vgaConfig;
  boot_iso = {
    type = "scsi";
    inherit iso_file;
    unmount = true;
  };

  inherit cores;

  memory = memoryMiB;

}
// (
  if useSerialInsteadOfVga then
    {
      serials = [ "socket" ];
    }
  else
    { }
)
