# Baseline profile for a small NixOS VM cloned from the nixos template.
# Mirrors the template's hardware config so clones start with a known-good baseline.
# Override any field in the per-host proxmox.nix via `small // { ... }`.
{
  # CPU
  cores = 2;
  sockets = 1;
  cpu = "host";
  kvm = 1;
  numa = 0;

  # Memory (MiB)
  memory = 2048;

  # Chipset / firmware
  machine = "q35";
  bios = "ovmf";

  # Storage controller
  scsihw = "virtio-scsi-single";

  # OS type — Linux 2.6+ (NixOS)
  ostype = "l26";

  # Console — serial socket so PVE shell and VGA both work via pvesh
  serial0 = "socket";
  vga = "type=serial0";

  # Hardware entropy source — prevents key-generation stalls on fresh boots
  rng0 = "source=/dev/urandom,max_bytes=1024,period=1000";

  # QEMU guest agent — enables clean shutdown, IP reporting, etc.
  agent = 1;

  # Start VM automatically when the host boots
  onboot = 1;

  # SMBIOS — human-readable strings; proxmox-sync base64-encodes them for PVE.
  # UUID is managed by PVE and preserved automatically on every write.
  smbios1 = "manufacturer=Leon Hubrich,product=PVE-Flake-VM";

  template = 10002;
}
