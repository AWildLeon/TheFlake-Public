{
  pkgs,
  lib,
  config,
  ...
}:
{

  config = lib.mkIf config.lh.desktop.environments.plasma.enable {
    environment.plasma6.excludePackages = with pkgs.kdePackages; [
      elisa
      okular
      kate
      gwenview
      plasma-browser-integration
      kinfocenter
      plasma-workspace-wallpapers
    ];

    services = {
      displayManager = {
        sddm = {
          enable = true;
          theme = "breeze";
        };
      };
      desktopManager.plasma6.enable = true;

    };
    home-manager.sharedModules = [
      {
        xdg.configFile = {
          "kxkbrc".text = ''
            [Layout]
            LayoutList=de
            Use=true
          '';
        };
        home.file.".local/share/konsole/Profile.profile".text = ''
          [Appearance]
          ColorScheme=WhiteOnBlack
          Font=NotoMono Nerd Font Mono,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1

          [Cursor Options]
          CursorShape=1

          [General]
          Command=/run/current-system/sw/bin/zsh
          Name=Profile
          Parent=FALLBACK/

          [Keyboard]
          KeyBindings=default

          [Scrolling]
          HistoryMode=2
        '';

      }
    ];
    programs.kdeconnect.enable = true;

    xdg.portal = {
      extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];
      config.common.default = "kde";
    };
  };

}
