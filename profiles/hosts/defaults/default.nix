{
  hostUses ? { },
  lib,
  ...
}:
{
  system.stateVersion = lib.mkDefault "25.11";

  users.groups.acme = { };

  lh = {
    cosmetic.stylix.enable = lib.mkDefault true;
    system.fhs-compat.enable = lib.mkDefault true;
    system.shell.enable = lib.mkDefault true;
    security.customca.enable = lib.mkDefault true;
    security.hardenProc.enable = lib.mkDefault true;
    security.hardenMisc.enable = lib.mkDefault true;
    cosmetic.motd.enable = lib.mkDefault true;
  };

  imports = [
    ./locale.nix
    ./nix-config.nix
    ./modules.nix
  ]
  ++ lib.optional (hostUses.homeManager or false) ./home_manager.nix;
}
// lib.optionalAttrs (hostUses.agenix or false) {
  age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
}
