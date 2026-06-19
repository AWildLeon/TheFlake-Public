{
  pkgs,
  inputs,
  lib,
  config,
  ...
}:
let
  cfg = config.lh.desktop.gaming;
in
{
  options.lh.desktop.gaming = {
    enable = lib.mkEnableOption "Desktop Gaming Support";
  };

  imports = [
    ./steam.nix
    ./minecraft.nix
    ./openrct.nix
  ];

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.bubblewrapped.discord
    ];

    # Use Flatpak for Discord and other gaming apps
    services.flatpak = {
      enable = true;
      # packages = [ "com.discordapp.Discord" ];
    };

    programs.gamemode.enable = true;
  };
}
