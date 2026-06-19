{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      rulesets = config.flake.nftablesConfigurations or { };
      names = builtins.attrNames rulesets;

      rendered = builtins.map (name: {
        name = "${name}.json";
        path = pkgs.writeText "${name}.json" (builtins.toJSON rulesets.${name});
      }) names;
    in
    {
      packages.nftables-rules = pkgs.linkFarm "nftables-rules" rendered;
    };
}
