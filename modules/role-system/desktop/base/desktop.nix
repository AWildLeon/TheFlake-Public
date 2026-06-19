{
  lib,
  config,
  pkgs,
  pkgsUnstable,
  ...
}:
let
  cfg = config.lh.desktop.base;
in
{
  options.lh.desktop.base = {
    enable = lib.mkEnableOption "Base Desktop Role";
  };

  config = lib.mkIf cfg.enable {
    security.sudo = {
      wheelNeedsPassword = false;
      enable = true;
    };

    programs.ausweisapp.enable = true;

    networking = {
      firewall.enable = false;
      networkmanager.enable = true;
      useDHCP = false;
      dhcpcd.enable = false;
    };

    environment.systemPackages = with pkgs; [
      libfido2
      exfatprogs
      anydesk
      virt-viewer
      remmina
      ffmpeg-full
      signal-desktop
      pkgsUnstable.tailscale
    ];

    lh.cosmetic.stylix-home-manager.enable = lib.mkDefault true;

    boot = {
      consoleLogLevel = 3;
      initrd.verbose = false;
      kernelParams = [
        "quiet"
        "splash"
        "boot.shell_on_fail"
        "udev.log_priority=3"
        "rd.systemd.show_status=auto"
      ];
      loader.timeout = lib.mkDefault 10;
    };

    fonts.packages = with pkgs; [
      nerd-fonts.noto
      nerd-fonts.fira-code
      nerd-fonts.dejavu-sans-mono
      nerd-fonts.hack
    ];
    programs = {
      openvpn3.enable = true;
      dconf.enable = true;
      # Appimage
      appimage = {
        enable = true;
        binfmt = true;
      };
    };

    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    services = {
      flatpak.enable = true;
      pcscd.enable = true;
      resolved.enable = true;
      avahi = {
        enable = true;
        nssmdns4 = true;
        openFirewall = true;
        publish = {
          enable = true;
          userServices = true;
        };
      };
    };

    lh.system.impermanence.persistentDirectories = [
      {
        directory = "/var/lib/tailscale";
        mode = "0700";
        user = "root";
        group = "root";
      }
    ];

    services.tailscale = {
      enable = true;
      package = pkgsUnstable.tailscale;
      useRoutingFeatures = "client";
      openFirewall = true;
      extraDaemonFlags = [
        "--no-logs-no-support"
      ];
      disableUpstreamLogging = true;
      disableTaildrop = true;
      extraSetFlags = [
        "--ssh=false"
        "--update-check=false"
        "--report-posture=false"
      ];
    };

    # Kernel
    boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_zen;
  };
}
