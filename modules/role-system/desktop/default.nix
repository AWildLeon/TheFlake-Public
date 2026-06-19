{ lib, config, ... }:
let
  cfg = config.lh.desktop;
in
{
  options.lh.desktop = {
    features = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "vr"
          "dev"
          "gaming"
          "media"
          "office"
          "audio"
        ]
      );
      default = [ ];
      description = "Enabled desktop features";
    };

    environment = lib.mkOption {
      type = lib.types.enum [
        "sway"
        "plasma"
        "none"
      ];
      default = "none";
      description = "Desktop environment to use";
    };
  };

  config = lib.mkIf (config.lh.roleSystem.systemType == "desktop") {
    lh.desktop = {
      # Enable base desktop role automatically
      base.enable = true;

      # Map features to enable options
      vr.enable = builtins.elem "vr" cfg.features;
      dev.enable = builtins.elem "dev" cfg.features;
      gaming.enable = builtins.elem "gaming" cfg.features;
      media.enable = builtins.elem "media" cfg.features;
      office.enable = builtins.elem "office" cfg.features;
      audio.enable = builtins.elem "audio" cfg.features;

      # Map environment
      environments.sway.enable = cfg.environment == "sway";
      environments.plasma.enable = cfg.environment == "plasma";
    };

    hardware.graphics.enable = true;

  };

  imports = [
    ./base/default.nix
    ./VR/default.nix
    ./dev/default.nix
    ./environments/plasma/default.nix
    ./environments/sway/default.nix
    ./gaming/default.nix
    ./media/default.nix
    ./office/default.nix
  ];
}
