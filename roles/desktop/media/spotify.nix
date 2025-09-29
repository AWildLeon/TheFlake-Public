{ spicetify-nix, pkgs, ... }:
let
  spicePkgs = spicetify-nix.legacyPackages.${pkgs.stdenv.system};
in
{
  imports = [ spicetify-nix.nixosModules.spicetify ];

  programs.spicetify = {
    enable = true;
    enabledExtensions = with spicePkgs.extensions; [
      hidePodcasts
      oldCoverClick
    ];
    enabledCustomApps = with spicePkgs.apps; [
      marketplace
      betterLibrary
    ];
    theme = spicePkgs.themes.text;
    colorScheme = "Gruvbox";
  };
}
