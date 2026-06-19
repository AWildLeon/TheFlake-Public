{
  modulesPath,
  pkgs,
  config,
  self,
  ...
}:
{

  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
  ];
  lh.roleSystem.systemType = "server";

  nix.settings = {
    sandbox = false;
  };

  proxmoxLXC = {
    manageNetwork = false;
    privileged = true;
  };

  services.fstrim.enable = false;

  system.stateVersion = "25.11";

  systemd.services."getty@tty1" = {
    overrideStrategy = "asDropin";
    serviceConfig.ExecStart = [
      ""
      "@${pkgs.util-linux}/sbin/agetty agetty --login-program ${config.services.getty.loginProgram} --autologin root --noclear --keep-baud %I 115200,38400,9600 $TERM"
    ];
  };

  services.qemuGuest.enable = false;
}
