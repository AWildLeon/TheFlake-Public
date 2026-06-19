{ lib, self }:
{
  mkInventorySshHosts = import ./mk-inventory-ssh-hosts.nix { inherit lib self; };
}
