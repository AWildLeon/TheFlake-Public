{ lib, config, ... }:
{
  options.lh.desktop.environments.plasma = {
    enable = lib.mkEnableOption "Plasma Desktop Environment";
  };

  imports = [
    # ../base
    ./plasma.nix
  ];
}
