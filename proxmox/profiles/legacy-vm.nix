# Baseline profile for the legacy SeaBIOS VM fleet (routers + older services).
# These VMs predate the OVMF/serial template and share a virtio-scsi-pci,
# BIOS-boot baseline with no serial console. Override per host via
# `legacy // { ... }`. cores/memory/cpu/networking are intentionally left to
# the per-host proxmox.nix since they vary widely across this fleet.
{
  # CPU / topology — cpu is set per host (x86-64-v3 on the router, host on pve1)
  sockets = 1;
  numa = 0;
  kvm = 1;

  # Chipset — SeaBIOS (no `bios` field) booting straight off the disk
  machine = "q35";
  boot = "c";

  # Storage controller
  scsihw = "virtio-scsi-pci";

  # OS type — Linux 2.6+ (NixOS)
  ostype = "l26";

  # QEMU guest agent + cloud-init user
  agent = 1;
  ciuser = "root";

  # Start VM automatically when the host boots
  onboot = 1;
}
