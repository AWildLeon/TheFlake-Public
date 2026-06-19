{ inputs, systems }:
{
  pkgsFor = builtins.listToAttrs (
    map (system: {
      name = system;
      value = import inputs.nixpkgs {
        inherit system;
        overlays = [ ];
      };
    }) systems
  );

  pkgsUnstableFor = builtins.listToAttrs (
    map (system: {
      name = system;
      value = import inputs.nixos-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    }) systems
  );
}
