{
  hostUses ? { },
  lib,
  ...
}:
{
  imports = [
    ./stylix.nix
  ]
  ++ lib.optional (hostUses.homeManager or false) ./stylix-home-manager.nix;
}
