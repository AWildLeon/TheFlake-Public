{ stylix
, pkgs
, ...
}:

{
  imports = [ stylix.nixosModules.stylix ];

  stylix = {
    enable = true;
    image = pkgs.fetchurl {
      url = "https://cdn.onlh.de/wallpaper.png";
      hash = "sha256-fhPZyRaShAIUBrZQBOvSa1Hk4RJaVehPMrF55wDklSY=";
    };
    targets.spicetify.enable = false;
    polarity = "dark";
    fonts = {
      serif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Serif";
      };

      sansSerif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Sans";
      };

      monospace = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Sans Mono";
      };

      emoji = {
        package = pkgs.noto-fonts-emoji;
        name = "Noto Color Emoji";
      };
    };
  };
}
