{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.lh.desktop.media;
in
{
  options.lh.desktop.media = {
    enable = lib.mkEnableOption "Desktop Media Tools";
  };

  config = lib.mkIf cfg.enable {
    # imports = [ ./spotify.nix ]; # File missing
    environment.systemPackages = with pkgs; [
      vlc
      gimp
      ffmpeg
      handbrake
    ];
  };
}
