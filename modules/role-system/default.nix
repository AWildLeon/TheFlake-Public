{
  config,
  hostdirname ? "",
  lib,
  ...
}:
let
  isDesktopHost = lib.hasPrefix "desktop." hostdirname;
in
{
  options.lh.roleSystem = {
    systemType = lib.mkOption {
      type = lib.types.enum [
        "server"
        "desktop"
        "router"
        "base"
      ];
      default = "base";
      description = "Select the system role type.";
    };
  };

  imports = [
    ./server
    ./router
  ]
  ++ lib.optional isDesktopHost ./desktop;
}
