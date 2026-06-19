{ pkgs, lib, ... }:
let
  cliphist_script = pkgs.writeScriptBin "clipboard_changer" ''
    ${builtins.readFile ./scripts/clipboard_changer.sh}
  '';

  sway_keys_script = pkgs.writeScriptBin "sway_keys" ''
    ${builtins.readFile ./scripts/sway_keys.sh}
  '';

  env = {
    NIXOS_OZONE_WL = "1";
    EDITOR = "code -w";
  };
in
{
  home = {

    pointerCursor = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = 24;
      x11 = {
        enable = true;
        defaultCursor = "Adwaita";
      };
      sway.enable = true;
    };
    sessionVariables = env;

    packages = with pkgs; [
      xfce.thunar
      qalculate-qt
      playerctl
      wl-clipboard
      papirus-icon-theme
      hicolor-icon-theme
      adwaita-icon-theme
    ];
  };

  systemd.user.sessionVariables = env;

  wayland.windowManager.sway = {
    package = pkgs.swayfx;
    enable = true;
    checkConfig = false;
    systemd.enable = true;
    extraSessionCommands = ''
      # Force Wayland for Java and Chromium-based apps
      export OZONE_PLATFORM=wayland
      export NIXOS_OZONE_WL=1
      export JBR_WAYLAND=1
      export _JAVA_AWT_WM_NONREPARENTING=1
      export JDK_JETBRAINS_CLIENT_ALLOCATE_WAYLAND=1
    '';
    extraConfig = ''
      corner_radius 8

      shadows enable
      shadows_on_csd disable
      shadow_blur_radius 20
      blur enable

      layer_effects "waybar" {
        shadows enable;
        corner_radius 0;
      }
    '';
    config = {
      modifier = "Mod1";
      bars = [ ];
      startup = [
        {
          command = "systemctl --user restart kanshi.service waybar.service || true";
          always = true;
        }
      ];
      window = {
        border = 1;
        hideEdgeBorders = "smart";
      };
      gaps = {
        #outer = 5;
        inner = 1;
      };
      floating.titlebar = true;
      input = {
        "type:keyboard" = {
          xkb_layout = "de";
        };
        "type:touchpad" = {
          tap = "enabled";
          drag_lock = "disabled";
          middle_emulation = "disabled";
          dwt = "enabled";
          accel_profile = "adaptive";
          pointer_accel = "0.2";
        };
        "type:pointer" = {
          accel_profile = "adaptive";
          pointer_accel = "0.2";
        };
      };
      keybindings =
        # let modifier = config.wayland.windowManager.sway.config.modifier; in
        lib.mkOptionDefault {
          "Mod4+space" = "exec ${pkgs.fuzzel}/bin/fuzzel";
          "Mod1+Ctrl+T" = "exec ${pkgs.ghostty}/bin/ghostty";
          "Mod4+V" = ''
            exec PATH=${pkgs.bash}/bin:${pkgs.wl-clipboard}/bin:${pkgs.fuzzel}/bin:${pkgs.coreutils}/bin:${pkgs.cliphist}/bin:${pkgs.findutils}/bin:${pkgs.gawk}/bin ${cliphist_script}/bin/clipboard_changer
          '';
          "Mod4+K" = ''
            exec PATH=${pkgs.bash}/bin:${pkgs.fuzzel}/bin:${pkgs.coreutils}/bin:${pkgs.gnused}/bin:${pkgs.gnugrep}/bin ${sway_keys_script}/bin/sway_keys increase
          '';

          "Mod4+L" = "${pkgs.swaylock}/bin/swaylock -f";

          "Print" =
            ''exec ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" - | ${pkgs.wl-clipboard}/bin/wl-copy'';

          # Brightness Controls
          "XF86MonBrightnessDown" = "exec light -U 10";
          "XF86MonBrightnessUp" = "exec light -A 10";

          # Volume Controls
          "XF86AudioRaiseVolume" = "exec ${pkgs.pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ +5%";
          "XF86AudioLowerVolume" = "exec ${pkgs.pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ -5%";
          "XF86AudioMute" = "exec ${pkgs.pulseaudio}/bin/pactl set-sink-mute @DEFAULT_SINK@ toggle";

          # Media keys (playerctl)
          "XF86AudioPlay" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
          "XF86AudioPause" = "exec ${pkgs.playerctl}/bin/playerctl pause";
          "XF86AudioNext" = "exec ${pkgs.playerctl}/bin/playerctl next";
          "XF86AudioPrev" = "exec ${pkgs.playerctl}/bin/playerctl previous";
          "XF86AudioStop" = "exec ${pkgs.playerctl}/bin/playerctl stop";
          "XF86Tools" = "exec spotify";
          "XF86Calculator" = "exec qalculate-qt";
          "XF86Search" = "exec brave";
        };
    };
  };

  gtk = {
    enable = true;
    iconTheme = {
      name = "Papirus";
      package = pkgs.papirus-icon-theme;
    };
  };
  programs = {

    fuzzel = {
      enable = true;
      settings = {
        main = {
          prompt = "-> ";
          match-mode = "fzf";
          icon-theme = "Papirus";
          sort-result = true;
          match-counter = true;
          lines = 12;
          width = 40;
          font = lib.mkForce "DejaVu Sans:size=18";
          use-bold = true;
          dpi-aware = "auto";
        };
        border = {
          width = 5;
          # radius = 12;
          # selection-radius = 6;
        };
      };
    };

    wlogout = {
      enable = true;
    };

    ghostty = {
      enable = true;
      systemd.enable = true;
      enableZshIntegration = true;
      settings = {
        theme = lib.mkForce "Ardoise";
        mouse-hide-while-typing = true;
        background-opacity = 0.5;
        confirm-close-surface = false;
        linux-cgroup = "always";
        clipboard-trim-trailing-spaces = true;
        window-decoration = "server";
        cursor-style = "block";
      };
    };

    swaylock = {
      enable = true;
      settings = { };
    };
  };
  services = {

    gnome-keyring.enable = true;

    cliphist = {
      enable = true;
    };

    blueman-applet.enable = true;
    network-manager-applet.enable = true;
    playerctld.enable = true;

    mako = {
      settings = {
        "actionable=true" = {
          anchor = "top-left";
        };
        actions = true;
        anchor = "top-right";
        border-radius = 0;
        default-timeout = 5000;
        height = 100;
        icons = true;
        ignore-timeout = false;
        layer = "top";
        margin = 10;
        markup = true;
        width = 300;
      };
      enable = true;
    };
  };

  systemd.user.services.mako = {
    Unit = {
      Description = "Mako notifier for Sway session";
      After = [ "sway-session.target" ];
      PartOf = [ "sway-session.target" ];
    };

    Service = {
      ExecStart = "${pkgs.mako}/bin/mako";
    };

    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };
}
