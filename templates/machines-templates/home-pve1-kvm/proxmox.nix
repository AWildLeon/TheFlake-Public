{ lib }:
lib.profiles.small
// rec {
  vmid = null;
  node = "pve1";

  cpu = "host";
  cores = 4;
  memory = 2048;

  boot = lib.mkBoot "virtio0";

  nameserver = "2a14:47c0:e002:1010::10 10.10.10.10";

  ipconfig0 = lib.mkIpConfigFromHost { };

  net0 = lib.mkNet "DMZ" {
    firewall = true;
    queues = cores;
  };

  tags = "colmena;dmz;linux;nixos";
  virtio0 = "discard=on,iothread=1,size=20G";
}
