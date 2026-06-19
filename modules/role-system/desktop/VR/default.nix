{ lib, config, ... }:
{
  options.lh.desktop.vr = {
    enable = lib.mkEnableOption "Desktop VR Support";
  };

  imports = [
    ./wivrn.nix
  ];
}
