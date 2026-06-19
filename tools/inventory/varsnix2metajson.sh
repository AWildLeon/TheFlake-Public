#!/usr/bin/env bash
set -euo pipefail

# Change this if your hosts live elsewhere
HOSTS_DIR="${1:-./hosts}"

# Find every vars.nix and emit a vars.json in the same directory
find "$HOSTS_DIR" -type f -name 'vars.nix' -print0 | while IFS= read -r -d '' vars; do
  dir="$(dirname "$vars")"
  host="$(basename "$dir")"
  out="$dir/meta.json"
  abs="$(realpath "$vars")"

  nix eval --json --impure --expr "
    let
      v = import ${abs};

      unique = xs:
        builtins.foldl'
          (acc: x: if builtins.elem x acc then acc else acc ++ [ x ])
          [ ]
          xs;

    in {
      deployment = {
        targetHost = v.deployment.targetHost;
        sshUser    = v.deployment.targetUser or \"root\";
        sshPort    = v.deployment.targetPort or 22;
        tags       = unique ([ \"${host}\" ] ++ (v.deployment.tags or []));
      };
    }
  " >"$out"

  echo "wrote: $out"
done
