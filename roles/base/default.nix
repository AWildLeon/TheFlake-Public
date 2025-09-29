{ lib, ... }: {
  imports = [
    ../../modules/core/nix-config.nix
    ../../modules/core/home-manager-base.nix
    ../../hardening/proc.nix
    ../../modules/core/locale.nix
    ../../modules/core/interactivesystem.nix
    ../../modules/system/shell.nix
    ../../modules
  ];

  lh = {
    cosmetic.stylix.enable = lib.mkDefault true;
    system.fhs-compat.enable = lib.mkDefault true;
    system.shell.enable = lib.mkDefault true;
    security.customca.enable = lib.mkDefault true;
    cosmetic.motd.enable = lib.mkDefault true;
  };
}
