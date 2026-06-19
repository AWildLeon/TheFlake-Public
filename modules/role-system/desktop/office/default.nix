{ lib, config, ... }:
{
  imports = [
    ./libreoffice.nix
  ];

  options.lh.desktop.office = {
    enable = lib.mkEnableOption "Desktop Office Suite";
  };
}
