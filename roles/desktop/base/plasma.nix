{ pkgs, ... }:
{


  environment.plasma6.excludePackages = with pkgs; [
    kdePackages.elisa
    kdePackages.okular
    kdePackages.kate
    kdePackages.gwenview
    kdePackages.plasma-browser-integration
  ];



  services = {
    displayManager = {
      sddm = {
        enable = true;
        theme = "breeze";
      };
    };
    desktopManager.plasma6.enable = true;
    xserver = {
      enable = true;
      xkb = {
        layout = "de";
      };
    };
  };
  #GTK Theming
  programs = {
    dconf.enable = true;
    kdeconnect.enable = true;
  };
  xdg.portal = {
    extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];
    config.common.default = "kde";
  };
}
