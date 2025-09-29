{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # Networking tools
    wget
    curl
    nmap
    arp-scan
    tcpdump
    dnsutils
    netcat
    socat
    rsync
    bmon
    iperf
    openssh
    dig

    # System monitoring
    htop
    btop
    strace
    powertop
    lsof

    # Editors
    nano
    screen

    # Utilities
    pciutils
    usbutils
    jq

    # Version control
    git
    git-lfs
    direnv

    # Nix
    nixfmt-tree
    nixfmt-classic
  ];
}
