{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.lh.printing.default;
in
{
  imports = [
    ./brother.nix
  ];

  options.lh.printing.default = {
    enable = lib.mkEnableOption "Enable default printing configuration";
  };

  config = lib.mkIf cfg.enable {
    hardware.sane = {
      enable = true;
    };

    services.printing = {
      enable = true;
      browsed.enable = true;
      browsing = true;
    };

    environment.systemPackages = with pkgs; [
      gscan2pdf
      sane-frontends
    ];
  };
}
