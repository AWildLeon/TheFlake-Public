# DNS zone merging utilities
# Scope: Deep merge functions for combining default zones with custom configurations
{ inputs }:
rec {
  # Deep merge function for DNS zones that concatenates lists instead of replacing them
  # Usage: mergeZone defaultZone overrideZone
  # Lists are concatenated, attribute sets are merged recursively
  mergeZone =
    default: override:
    let
      inherit (inputs.nixpkgs.lib) isAttrs isList;

      merge =
        lhs: rhs:
        if isAttrs lhs && isAttrs rhs then
          # Both are attribute sets: merge recursively
          let
            allKeys = builtins.attrNames lhs ++ builtins.attrNames rhs;
            uniqueKeys = inputs.nixpkgs.lib.unique allKeys;
          in
          builtins.listToAttrs (
            builtins.map (key: {
              name = key;
              value =
                if builtins.hasAttr key lhs && builtins.hasAttr key rhs then
                  merge lhs.${key} rhs.${key}
                else if builtins.hasAttr key lhs then
                  lhs.${key}
                else
                  rhs.${key};
            }) uniqueKeys
          )
        else if isList lhs && isList rhs then
          # Both are lists: concatenate them
          lhs ++ rhs
        else
          # Otherwise: override takes precedence
          rhs;
    in
    merge default override;

  # Merge a zone with defaults, but with explicit override capability
  # Usage: mergeZoneWithDefaults { defaults = import ./defaults.nix; zone = { ... }; forceOverride = ["MX"]; }
  # Lists are normally concatenated, but fields in forceOverride are replaced instead
  mergeZoneWithDefaults =
    {
      defaults,
      zone,
      forceOverride ? [ ], # List of keys to replace instead of merge (e.g., ["MX", "TXT"])
    }:
    let
      inherit (inputs.nixpkgs.lib) isAttrs isList elem;

      merge =
        path: lhs: rhs:
        let
          currentKey = if path != [ ] then builtins.head (inputs.nixpkgs.lib.reverseList path) else null;
          shouldOverride = currentKey != null && elem currentKey forceOverride;
        in
        if shouldOverride then
          rhs
        else if isAttrs lhs && isAttrs rhs then
          # Both are attribute sets: merge recursively
          let
            allKeys = builtins.attrNames lhs ++ builtins.attrNames rhs;
            uniqueKeys = inputs.nixpkgs.lib.unique allKeys;
          in
          builtins.listToAttrs (
            builtins.map (key: {
              name = key;
              value =
                if builtins.hasAttr key lhs && builtins.hasAttr key rhs then
                  merge (path ++ [ key ]) lhs.${key} rhs.${key}
                else if builtins.hasAttr key lhs then
                  lhs.${key}
                else
                  rhs.${key};
            }) uniqueKeys
          )
        else if isList lhs && isList rhs then
          # Both are lists: concatenate them
          lhs ++ rhs
        else
          # Otherwise: override takes precedence
          rhs;
    in
    merge [ ] defaults zone;
}
