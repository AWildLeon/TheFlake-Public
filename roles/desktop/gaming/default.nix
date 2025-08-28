{ pkgs, ... }:
{
  imports = [
    ./steam.nix
  ];
  environment.systemPackages = with pkgs; [
    discord
  ];

  services.flatpak.enable = true;
}
