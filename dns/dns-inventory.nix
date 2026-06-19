#
# DNS inventory: builds flake.dnsConfigurations live by walking dns/zones/* at
# evaluation time (no codegen step). Each subdirectory containing a zone.nix
# becomes a zone keyed by the directory name.
#
{ inputs, config, ... }:
let
  helpers = import ./helpers { inherit inputs; };

  zonesDir = ./zones;
  entries = builtins.readDir zonesDir;

  zoneNames = builtins.filter (
    n: entries.${n} == "directory" && builtins.pathExists (zonesDir + "/${n}/zone.nix")
  ) (builtins.attrNames entries);
in
{
  flake.lh.lib.dns = helpers;

  flake.dnsConfigurations = builtins.listToAttrs (
    map (name: {
      inherit name;
      value = import (zonesDir + "/${name}/zone.nix") {
        inherit inputs;
        lh = config.flake.lh;
      };
    }) zoneNames
  );
}
