{ pkgs, plasma-manager, ... }: {

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
      xkb = { layout = "de"; };
    };
  };

  services.resolved = { enable = true; };

  programs = {
    dconf.enable = true;
    thunderbird.enable = true;
    kdeconnect.enable = true;
  };
  xdg.portal = {
    extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];
    config.common.default = "kde";
  };

  home-manager.sharedModules =
    [ ./plasma-manager.nix plasma-manager.homeManagerModules.plasma-manager ];

  fonts.packages = with pkgs; [
    nerd-fonts.noto
    nerd-fonts.fira-code
    nerd-fonts.dejavu-sans-mono
    nerd-fonts.hack
  ];
}
