{ pkgs, ... }:
{
  programs.plasma = {
    enable = true;
    configFile = {
      "dolphinrc"."General"."RememberOpenedTabs" = false;
      "dolphinrc"."General"."ShowFullPath" = true;
      "dolphinrc"."KFileDialog Settings"."Places Icons Auto-resize" = false;
      "dolphinrc"."KFileDialog Settings"."Places Icons Static Size" = 22;
    };

    kwin = {
      edgeBarrier = 0; # Disables the edge-barriers introduced in plasma 6.1
      cornerBarrier = false;
    };
  };

  programs.konsole = {
    enable = true;
    profiles = {
      "Konsole" = {
        command = "${pkgs.zsh}/bin/zsh";
        font.name = "Hack Nerd Font";
        colorScheme = "Solarized";
      };
    };
    defaultProfile = "Konsole";
  };
}
