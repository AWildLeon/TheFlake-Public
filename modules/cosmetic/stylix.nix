{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.lh.cosmetic.stylix;
in
{
  options.lh.cosmetic.stylix = {
    enable = mkEnableOption "Enable Stylix system-wide theming";

    wallpaperUrl = mkOption {
      type = types.str;
      default = "https://cdn.onlh.de/wallpaper.jpg";
      description = "URL to download wallpaper from";
    };

    wallpaperHash = mkOption {
      type = types.str;
      default = "sha256-wEYzhjHCtdDvx0Dc7KTtWfWFvGhRQNLyBM1N8QwyaWc=";
      description = "Hash of the wallpaper file";
    };

    polarity = mkOption {
      type = types.enum [
        "light"
        "dark"
      ];
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
          default = pkgs.noto-fonts-color-emoji;
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

      base16Scheme = {
        scheme = "Artemis Moon";
        author = "Leon";
        base00 = "0a0a0c"; # Hintergrund
        base01 = "4b6e7f"; # Etwas heller
        base02 = "2e2e38"; # Selektierter BG
        base03 = "888898"; # Kommentare – jetzt hell genug für dunklen BG
        base04 = "a8a8b8"; # Sekundärtext
        base05 = "d0d0da"; # Haupttext
        base06 = "e4e4ee"; # Heller Text
        base07 = "f2f2f8"; # Hellstes
        base08 = "a0bcd0"; # Akzent Blaugrau
        base09 = "90aec4"; # Zahlen
        base0A = "b8d0e0"; # Keywords / Warnungen
        base0B = "90c8b0"; # Strings
        base0C = "a4c4d4"; # Escape
        base0D = "c0d8e8"; # Funktionen – hellstes Blau
        base0E = "9aaccc"; # Keywords
        base0F = "7090a8"; # Deprecated
      };
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
