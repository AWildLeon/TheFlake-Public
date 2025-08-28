{ pkgs, lib, ... }:
{

  security.sudo.wheelNeedsPassword = false;
  services = {
    flatpak.enable = true;
    # Enable CUPS to print documents.
    printing.enable = true;

  };

  # Disable The firewall
  networking.firewall.enable = false;

  # Allow 32Bit Steam games to work
  nixpkgs.config = {
    allowUnfree = true;
    allowUnsupportedSystem = true;
    supportedSystems = [
      "x86_64-linux"
      "i686-linux"
    ];
  };

  environment.systemPackages = with pkgs; [
    libfido2

    # Exfat Support
    exfatprogs
    wineWowPackages.stable
    brave
    anydesk
    virt-viewer
    remmina
    ffmpeg-full
    mkvtoolnix
    signal-desktop
  ];
  networking = {
    networkmanager = {
      enable = true;
      # wifi.backend = "iwd";
    };
    # use iNet Wireless Daemon (instead of wpa_supplicant) for wireless device management
    # wireless.iwd = {
    #   enable = true;

    #   # All options: https://iwd.wiki.kernel.org/networkconfigurationsettings
    #   settings = {
    #     Network = {
    #       EnableIPv6 = true;
    #       RoutePriorityOffset = 300;
    #     };
    #     Settings = {
    #       AutoConnect = true;
    #       #          Hidden = true;
    #       AlwaysRandomizeAddress = true;
    #     };
    #   };
    # };
  };

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Yubikey
  # services.pcscd.enable = true;

  # Newer Kernel
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  # Appimage
  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      userServices = true;
    };
  };
}
