{
  pkgs,
  lib,
  config,
  ...
}:
{
  config = lib.mkIf config.lh.desktop.environments.sway.enable {
    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd 'sway --unsupported-gpu'";
          user = "greeter";
        };
      };
    };
  };
}
