{
  hostUses ? { },
  inputs,
  lib,
  self,
  ...
}:
{
  imports = [
    (self + /modules)

    inputs.glance-ical-events.nixosModules.default
    inputs.stylix.nixosModules.stylix
    inputs.disko.nixosModules.disko
    inputs.impermanence.nixosModules.impermanence
    inputs.notnft.nixosModules.default
  ]
  ++ lib.optional (hostUses.agenix or false) inputs.agenix.nixosModules.default
  ++ lib.optional (hostUses.homeManager or false) inputs.home-manager.nixosModules.home-manager;

}
