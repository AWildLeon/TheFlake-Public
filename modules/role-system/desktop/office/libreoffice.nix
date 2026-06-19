{
  pkgs,
  lib,
  config,
  ...
}:
{
  config = lib.mkIf config.lh.desktop.office.enable {
    environment.systemPackages = with pkgs; [
      libreoffice
    ];
  };
}
