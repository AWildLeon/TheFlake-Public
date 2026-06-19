_: {
  flake = {
    nixosModule.default = import ./default.nix;
  };

  perSystem =
    { pkgs, lib, ... }:
    {
      packages.remotedesktopmanager = pkgs.callPackage ./packages/remotedesktopmanager { };
    };
}
