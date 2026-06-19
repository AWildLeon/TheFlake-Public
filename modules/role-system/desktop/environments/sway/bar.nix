{ pkgs, ... }:
{
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    # systemd.enableInspect = true;
    # style = ''
    #   .hidden {
    #     display: none;
    #   }
    # '';
    settings = {
      mainBar = {
        layer = "top";
        height = 30;
        ipc = true;
        reload_style_on_change = true;
        spacing = 3;
        modules-left = [
          "idle_inhibitor"
          "battery"
          "network"
        ];
        modules-center = [ "sway/window" ];
        modules-right = [
          "mpd"
          "wireplumber"
          # "cpu"
          # "memory"
          "backlight"
          "tray"
          "clock"
          "custom/power"
        ];

        keyboard-state = {
          numlock = true;
          capslock = true;
          format = "{name} {icon}";
          format-icons = {
            locked = "";
            unlocked = "";
          };
        };
        "sway/mode" = {
          format = ''<span style="italic">{}</span>'';
        };
        "sway/scratchpad" = {
          format = "{icon} {count}";
          show-empty = false;
          format-icons = [
            ""
            ""
          ];
          tooltip = true;
          tooltip-format = "{app}: {title}";
        };
        idle_inhibitor = {
          format = "{icon}";
          format-icons = {
            activated = "  ";
            deactivated = "  ";
          };
        };
        battery = {
          format = "{capacity}%";
          format-charging = " {capacity}%";
          format-full = " {capacity}%";
          interval = 10;
          # bat = "BAT1";
        };
        tray = {
          spacing = 10;
        };
        clock = rec {
          tooltip-format = ''
            <big>{:%Y %B}</big>
            <tt><small>{calendar}</small></tt>'';
          format-alt = format;
          format = "{:%H:%M %d.%m.%Y}";
          calendar = {
            mode = "year";
            mode-mon-col = 3;
            weeks-pos = "right";
            on-scroll = 1;
            format = {
              months = "<span color='#ffead3'><b>{}</b></span>";
              days = "<span color='#ecc6d9'><b>{}</b></span>";
              weeks = "<span color='#99ffdd'><b>W{}</b></span>";
              weekdays = "<span color='#ffcc66'><b>{}</b></span>";
              today = "<span color='#ff6699'><b><u>{}</u></b></span>";
            };
          };
        };
        cpu = {
          format = "{usage}% ";
          tooltip = false;
        };
        memory = {
          format = "{}% ";
        };

        wireplumber = {
          scroll-step = 5;
          format = "{volume}% {icon} {format_source}";
          format-bluetooth = "{volume}% {icon} {format_source}";
          format-bluetooth-muted = " {icon} {format_source}";
          node-type = "Audio/Sink";
          format-source = "";
          max-volume = 120.0;
          format-icons = {
            headphone = "";
            headset = "";
            default = [
              ""
              ""
              ""
            ];
          };
          on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
        };
        "backlight" = {
          format = "{percent}% {icon}";
          "format-icons" = [ " " ];
          tooltip = false;
        };

        "custom/power" = {
          format = "⏻ ";
          tooltip = false;
          on-click = "${pkgs.wlogout}/bin/wlogout";
        };

        network = {
          format = "{ifname}";
          format-wifi = "{essid} ({signalStrength}%)  ";
          format-ethernet = "{ipaddr}/{cidr}  ";
          format-disconnected = "N/A  ";
          tooltip-format = "{ifname} via {gwaddr}  ";
          tooltip-format-wifi = "{essid} ({signalStrength}%)  ";
          tooltip-format-ethernet = "{ifname}  ";
          tooltip-format-disconnected = "Click to connect to a network";
          max-length = 50;
          on-click = "${pkgs.networkmanagerapplet}/bin/nm-connection-editor";
        };
      };
    };
  };
}
