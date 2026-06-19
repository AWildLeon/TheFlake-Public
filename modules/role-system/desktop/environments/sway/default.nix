{ lib, config, ... }:
let
  cfg = config.lh.desktop.environments.sway;
in
{
  options.lh.desktop.environments.sway = {
    enable = lib.mkEnableOption "Sway Desktop Environment";
  };

  imports = [
    # ../base # Handled centrally
    ./sway-system.nix
    ./greeter.nix
  ];

  config = lib.mkIf cfg.enable {
    home-manager.sharedModules = [
      ./sway-homemanager.nix
      ./bar.nix
    ];

    xdg.portal = {
      enable = true;
      wlr.enable = true;
    };

    services.gnome.gnome-keyring.enable = true;
    services.power-profiles-daemon.enable = true;
    services.blueman.enable = true;
    services.playerctld.enable = true;
    services.gvfs.enable = true;

    security = {
      polkit.enable = true;

      # this allows any program run by the "users" group to request real-time priority.
      pam.loginLimits = [
        {
          domain = "@users";
          item = "rtprio";
          type = "-";
          value = 1;
        }
      ];
    };
  };
}
