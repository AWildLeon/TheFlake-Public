{
  pkgs,
  lib,
  config,
  ...
}:
{
  config = lib.mkIf config.lh.desktop.gaming.enable {
    environment.systemPackages = with pkgs; [
      prismlauncher
      jdk21
      jre8
      jdk17
    ];
  };
}
