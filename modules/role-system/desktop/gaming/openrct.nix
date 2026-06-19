{
  pkgs,
  lib,
  config,
  ...
}:
{
  config = lib.mkIf config.lh.desktop.gaming.enable {
    environment.systemPackages = with pkgs; [
      openrct2
    ];
  };
}
