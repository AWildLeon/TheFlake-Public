{ lib, ... }: {

  security.sudo.enable = false;
  environment.defaultPackages = lib.mkForce [ ];
  systemd.coredump.enable = false;

  #  security.apparmor.enable = true;
  #  security.apparmor.killUnconfinedConfinables = true;

}
