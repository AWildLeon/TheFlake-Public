_: {
  fileSystems."/proc" = {
    fsType = "proc";
    device = "proc";
    options = [
      "nosuid"
      "nodev"
      "noexec"
      "hidepid=2"
    ];
    neededForBoot = true;
  };

  # Allow only root for /proc
  users.groups.proc = { };
  systemd.services.systemd-logind.serviceConfig = {
    SupplementaryGroups = [ "proc" ];
  };
}
