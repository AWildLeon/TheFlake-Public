{
  inputs,
  config,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    let
      zones = config.flake.dnsConfigurations or { };
      zoneNames = builtins.attrNames zones;

      rendered = builtins.map (name: {
        name = "${name}.zone";
        path = pkgs.writeText "${name}.zone" (inputs.dns.lib.toString name zones.${name});
      }) zoneNames;
    in
    {
      packages.dns-zones = pkgs.linkFarm "dns-zones" rendered;
    };
}
