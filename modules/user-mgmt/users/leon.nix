{
  lib,
  config,
  inputs,
  ...
}:

with lib;

let
  cfg = config.lh.users.leon;
in
{
  options.lh.users.leon = {
    enable = mkEnableOption "Enable Leon user account";
    disableHomeManager = mkOption {
      type = types.bool;
      default = false;
      description = "Disable Home Manager configuration for Leon";
    };

    desktop = mkEnableOption "Enable desktop configuration for Leon";

    autoLogin = mkOption {
      type = types.bool;
      default = true;
      description = "Enable auto-login for Leon user";
    };

    sudoNoPassword = mkOption {
      type = types.bool;
      default = true;
      description = "Enable passwordless sudo for Leon";
    };

    extraGroups = mkOption {
      type = types.listOf types.str;
      default = [
        "users"
        "wheel"
      ];
      description = "Additional groups for Leon user";
    };
  };

  config = mkIf cfg.enable {
    users = {
      # Base user configuration
      users.leon = {
        isNormalUser = true;
        description = "Leon Hubrich";
        password = "1234"; # TODO: Change out with Password file with real PW.
        openssh.authorizedPrincipals = [
          "mail@example.com"
          "nixarchitect@example.com"
        ];
        group = "leon";
        createHome = true;
        uid = 1000;
        home = "/home/leon";
        extraGroups =
          cfg.extraGroups
          ++ (optionals cfg.desktop [
            "networkmanager"
            "dialout"
            "video"
            "render"
          ])
          ++ (optionals config.programs.gamemode.enable [ "gamemode" ])
          ++ (optionals config.virtualisation.docker.enable [ "docker" ])
          ++ (optionals config.hardware.sane.enable [
            "scanner"
            "lp"
          ]);
      };

      # Desktop-specific group
      groups.leon.gid = 1000;
    };
    nix.settings = {
      trusted-users = [
        "leon"
      ];
      allowed-users = [
        "leon"
      ];
    };

    # Auto-login configuration
    services.displayManager.autoLogin.user = mkIf (cfg.autoLogin && cfg.desktop) "leon";

    # Sudo configuration
    security.sudo = mkIf cfg.sudoNoPassword {
      execWheelOnly = true;
      enable = mkForce true;
      extraRules = [
        {
          users = [ "leon" ];
          commands = [
            {
              command = "ALL";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
    };

    # Home Manager configuration
    home-manager.users.leon = mkIf (!cfg.disableHomeManager) (
      if cfg.desktop then inputs.self.homeModules.leon_desktop else inputs.self.homeModules.leon_cli
    );

  };
}
