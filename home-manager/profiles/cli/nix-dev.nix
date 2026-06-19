{ inputs, pkgs, ... }:
{
  home.packages = with pkgs; [
    nixfmt
    inputs.colmena.packages.${pkgs.stdenv.hostPlatform.system}.colmena
    inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.home-manager
    direnv
    git
    nixd
    step-cli
  ];
}
