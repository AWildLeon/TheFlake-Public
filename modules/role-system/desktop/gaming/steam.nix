{ lib, config, ... }:
{
  config = lib.mkIf config.lh.desktop.gaming.enable {
    programs.steam = {
      enable = true;
    };

    nixpkgs.config = {
      # Allow 32Bit Steam games to work
      supportedSystems = [
        "x86_64-linux"
        "i686-linux"
      ];
    };
  };
}
