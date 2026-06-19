{ inputs, pkgs, ... }:
{
  home.packages = [
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.bubblewrapped.spotify
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.bubblewrapped.discord
  ];

  services.kdeconnect.enable = true;
}
