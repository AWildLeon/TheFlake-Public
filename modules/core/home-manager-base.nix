{ home-manager
, ts
, ...
}:
{
  imports = [
    home-manager.nixosModules.home-manager
  ];

  home-manager.backupFileExtension = "hm-bak-${ts}";
}
