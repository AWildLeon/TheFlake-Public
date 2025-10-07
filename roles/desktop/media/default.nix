{ pkgs, ... }: {
  imports = [ ./spotify.nix ];

  environment.systemPackages = with pkgs; [ vlc gimp ffmpeg handbrake ];
}
