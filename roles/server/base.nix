{ ... }:
{
  imports = [
    ../../modules/system/shell.nix
    ../../hardening/guestagent.nix
    ../../modules/security/ssh.nix
    ../../modules/core/locale.nix
    ../../modules/core/interactivesystem.nix
    ../../secrets/agenix.nix
    ../../modules/cosmetic/stylix.nix
    ../../modules/cosmetic/motd-and-issue.nix
    ../../modules/services
    ../../hardening/misc.nix
    ../../hardening/proc.nix
  ];
}
