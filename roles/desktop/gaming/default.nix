{ ... }:
{
  imports = [
    ./steam.nix
  ];
  # environment.systemPackages = with pkgs; [
  # discord
  # ];


  # Use Flatpak for Discord and other gaming apps
  services.flatpak = {
    enable = true;
    packages = [
      "com.discordapp.Discord"
    ];
  };
}
