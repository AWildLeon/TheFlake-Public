{
  lib,
  config,
  pkgs,
  ...
}:
{
  config = lib.mkIf (config.lh.roleSystem.systemType == "server") {
    lh = {
      security.ssh.enable = lib.mkDefault true;
    };
    networking.nftables.enable = lib.mkDefault true;
    security.acme.defaults.email = "acme@example.com";

    boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_xanmod_stable;
    boot.kernel.sysctl = {
      # Autogroup aus (Desktop-Feature, für Server sinnlos)
      "kernel.sched_autogroup_enabled" = 0;
      # Memory
      "vm.swappiness" = 60;
      "vm.vfs_cache_pressure" = 100;
    };
  };

  imports = [
    ./docker.nix
  ];
}
