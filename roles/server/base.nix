{ lib, ... }:
{
  imports = [
    ../base
    ../../hardening/guestagent.nix
    ../../secrets/agenix.nix
    ../../hardening/misc.nix
  ];
  lh.security.ssh.enable = lib.mkDefault true;
  lh.cosmetic.motd.enable = lib.mkDefault true;
}
