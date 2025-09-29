{ lib, config, ... }:

with lib;

let
  cfg = config.lh.users.leon;
in
{
  options.lh.users.leon = {
    enable = mkEnableOption "Enable Leon user account";

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
      default = [ "users" "wheel" ];
      description = "Additional groups for Leon user";
    };
  };

  config = mkIf cfg.enable
    {
      # Base user configuration
      users.users.leon = {
        isNormalUser = true;
        description = "Leon Hubrich";
        group = "leon";
        uid = 1000;
        home = "/home/leon";
        extraGroups = cfg.extraGroups ++
          (optionals cfg.desktop [ "networkmanager" "dialout" ]) ++
          (optionals config.virtualisation.docker.enable [ "docker" ]);
      };

      # Desktop-specific group
      users.groups.leon.gid = 1000;

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

      # Home Manager configuration (desktop only)
      home-manager.users.leon = mkIf cfg.desktop (import ./leon-hm.nix);

    };
}
