{
  inputs,
  config,
  lib,
  ...
}:
let
  pkgs = import ./pkgs.nix {
    inherit inputs;
    inherit (config) systems;
  };
in
{
  options.flake.lh = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf lib.types.raw);
    default = { };
  };

  config.flake.lh.lib.pkgsFor = pkgs.pkgsFor;
  config.flake.lh.lib.pkgsUnstableFor = pkgs.pkgsUnstableFor;
}
