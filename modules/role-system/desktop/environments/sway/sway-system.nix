{
  pkgs,
  lib,
  config,
  ...
}:
{
  config = lib.mkIf config.lh.desktop.environments.sway.enable {
    programs.sway = {
      enable = true;
      package = null; # Manage from Home-Manager
      wrapperFeatures.gtk = true;
      extraPackages = with pkgs; [
        adwaita-icon-theme # mouse cursor and icons
        gnome-themes-extra # dark adwaita theme

      ];
    };
    programs.light.enable = true;

    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-color-emoji
      font-awesome
      source-han-sans
      source-han-serif
    ];

  };
}
