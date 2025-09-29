{ lib, config, pkgs, ... }:

with lib;

let
  cfg = config.lh.cosmetic.stylix;
in
{
  options.lh.cosmetic.stylix = {
    enable = mkEnableOption "Enable Stylix system-wide theming";

    wallpaperUrl = mkOption {
      type = types.str;
      default = "https://cdn.onlh.de/wallpaper.png";
      description = "URL to download wallpaper from";
    };

    wallpaperHash = mkOption {
      type = types.str;
      default = "sha256-fhPZyRaShAIUBrZQBOvSa1Hk4RJaVehPMrF55wDklSY=";
      description = "Hash of the wallpaper file";
    };

    polarity = mkOption {
      type = types.enum [ "light" "dark" ];
      default = "dark";
      description = "Color scheme polarity";
    };

    disableSpicetify = mkOption {
      type = types.bool;
      default = true;
      description = "Disable Stylix theming for Spicetify";
    };

    fonts = {
      serif = {
        package = mkOption {
          type = types.package;
          default = pkgs.dejavu_fonts;
          description = "Package containing serif font";
        };

        name = mkOption {
          type = types.str;
          default = "DejaVu Serif";
          description = "Name of serif font";
        };
      };

      sansSerif = {
        package = mkOption {
          type = types.package;
          default = pkgs.dejavu_fonts;
          description = "Package containing sans-serif font";
        };

        name = mkOption {
          type = types.str;
          default = "DejaVu Sans";
          description = "Name of sans-serif font";
        };
      };

      monospace = {
        package = mkOption {
          type = types.package;
          default = pkgs.dejavu_fonts;
          description = "Package containing monospace font";
        };

        name = mkOption {
          type = types.str;
          default = "DejaVu Sans Mono";
          description = "Name of monospace font";
        };
      };

      emoji = {
        package = mkOption {
          type = types.package;
          default = pkgs.noto-fonts-emoji;
          description = "Package containing emoji font";
        };

        name = mkOption {
          type = types.str;
          default = "Noto Color Emoji";
          description = "Name of emoji font";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    stylix = {
      enable = true;
      image = pkgs.fetchurl {
        url = cfg.wallpaperUrl;
        hash = cfg.wallpaperHash;
      };
      targets.spicetify.enable = !cfg.disableSpicetify;
      inherit (cfg) polarity;
      fonts = {
        serif = {
          inherit (cfg.fonts.serif) package;
          inherit (cfg.fonts.serif) name;
        };

        sansSerif = {
          inherit (cfg.fonts.sansSerif) package;
          inherit (cfg.fonts.sansSerif) name;
        };

        monospace = {
          inherit (cfg.fonts.monospace) package;
          inherit (cfg.fonts.monospace) name;
        };

        emoji = {
          inherit (cfg.fonts.emoji) package;
          inherit (cfg.fonts.emoji) name;
        };
      };
    };

    # Fix systemd-vconsole-setup service ordering
    systemd.services.systemd-vconsole-setup = {
      after = [ "systemd-tmpfiles-setup.service" ];
      wants = [ "systemd-tmpfiles-setup.service" ];
    };
  };
}
