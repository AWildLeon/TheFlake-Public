{
  hostUses ? { },
  inputs,
  lib,
  ...
}:
{
  imports = [
    ./networking
    ./services
    ./system
    ./router
    ./security
    ./helper
    ./cosmetic
    ./packages
    ./role-system
    ./printing
    inputs.lh-nixlib.nixosModule.default
    inputs.lhzsh.nixosModules.default
  ]
  ++ lib.optional (hostUses.homeManager or false) ./user-mgmt;
}
