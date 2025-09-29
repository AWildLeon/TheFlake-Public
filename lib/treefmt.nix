# Treefmt configuration
{ inputs, ... }:
let
  inherit (inputs) nixpkgs treefmt-nix;
in
{
  mkTreefmt = treefmt-nix.lib.evalModule nixpkgs.legacyPackages.x86_64-linux {
    projectRootFile = "flake.nix";
    programs = {
      nixpkgs-fmt.enable = true;
      prettier = {
        enable = true;
        includes = [
          "*.md"
          "*.yaml"
          "*.yml"
          "*.json"
        ];
      };
      shfmt = {
        enable = true;
        indent_size = 2;
      };
    };
    settings.global.excludes = [
      # Exclude shell scripts from shellcheck for now due to configuration issues
      "*.sh"
      # Exclude Glance YAML files from prettier due to custom syntax
      "**/glance/**/*.yml"
    ];
  };
}
