# Main library entrypoint
{ inputs, self }:
let
  inherit (inputs) nixpkgs;
in
{
  # Import all library modules
  systems = import ./systems.nix { inherit inputs self; };
  hostDiscovery = import ./host-discovery.nix { inherit inputs self; };
  deployment = import ./deployment.nix { inherit inputs self; };
  devShell = import ./dev-shell.nix { inherit inputs self; };
  treefmt = import ./treefmt.nix { inherit inputs self; };
  apps = import ./apps.nix { inherit inputs self; };

  # Common utilities
  inherit (nixpkgs.lib)
    genAttrs
    optionalAttrs
    optionals
    mkDefault
    mkForce;

  # Helper paths for configurations
  paths = {
    modules = path: self + "/modules" + path;
    roles = path: self + "/roles" + path;
    root = path: self + path;
  };

  # Helper for supported systems
  supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
  forEachSystem = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
}
