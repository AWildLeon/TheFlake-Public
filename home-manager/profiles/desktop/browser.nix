{ pkgs, ... }:
{
  programs.chromium = {
    enable = true;
    package = pkgs.brave;
  };

  home.packages = with pkgs; [
    vulkan-loader
    vulkan-tools
  ];
}
