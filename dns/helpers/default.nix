# DNS helpers - Main entry point
# Combines network address extraction, DNS record creation, and zone merging utilities
{ inputs }:
let
  # Network address extraction utilities
  network = import ./network.nix { inherit inputs; };

  # DNS record creation from machine configurations
  records = import ./records.nix { inherit inputs network; };

  # Zone merging utilities
  merge = import ./merge.nix { inherit inputs; };
in
# Export all utilities in a flat namespace for convenience
network // records // merge
