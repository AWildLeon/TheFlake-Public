#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Check for nixos
if [[ -f /etc/NIXOS ]]; then
  echo "NixOS detected, skipping Home Manager installation."
  echo "Please use the NixOS module for Home Manager instead."
  exit 0
fi

# Check for nix
if ! hash nix &>/dev/null; then
  echo "Nix is not installed. Please install Nix before running this script."
  echo "You can install Nix by following the instructions at https://nixos.org/download/"
  exit 1
fi

CONFIGURATIONS=$(nix eval .#homeConfigurations --apply 'x: builtins.concatStringsSep "\n" (builtins.attrNames x)' --raw)
hm_rev=$(nix eval --raw --impure --expr '(builtins.getFlake (toString ./.)).inputs.home-manager.rev')
flake_lastmodifyed=$(nix eval --raw --impure --expr '(builtins.getFlake (toString ./.)).lastModifiedDate')

hm() {
  nix run "github:nix-community/home-manager/${hm_rev}" -- "$@"
}

printf '%s\n' "$CONFIGURATIONS" | fzf --preview 'echo {}' --header="Select a Home Manager configuration" --preview-window=hidden | while read -r config; do
  echo "Switching to configuration: $config"
  hm switch --flake .#"$config" -b "bak-$flake_lastmodifyed"
done
