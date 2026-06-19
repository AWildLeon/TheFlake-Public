{
  pkgs,
  pkgsUnstable,
  lib,
  config,
  ...
}:
let
  cfg = config.lh.desktop.dev;
in
{
  options.lh.desktop.dev = {
    enable = lib.mkEnableOption "Desktop Development Tools";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      jetbrains-toolbox
      nil
      gitkraken
      pkgsUnstable.jetbrains.rider
    ];
  };
}
