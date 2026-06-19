#!/usr/bin/env bash

config="$HOME/.config/sway/config"

width=100

# Modifier-Übersetzung
translate_modifiers() {
  sed 's/Mod1/Alt/g; s/Mod4/Super/g'
}

# Entferne /nix/store/.../bin/
strip_nix_store() {
  sed -E 's#/nix/store/[a-z0-9]{32}-[^/]+/bin/##g'
}

# Entferne komplette PATH=… Konstrukte
strip_path_envs() {
  sed -E 's#PATH=[^ ]+ ##g'
}

# Extrahiere bindsym-Zeilen
keybinds=$(
  grep -E "^bindsym" "$config" |
    sed 's/^bindsym\s\+//' |
    translate_modifiers |
    strip_nix_store |
    strip_path_envs |
    sed 's/\s\+exec\s\+/\t→ exec: /' |
    sed 's/\s\+/\t→ /'
)

# Falls nichts da ist
[ -z "$keybinds" ] && {
  echo "No keybindings found." |
    fuzzel --dmenu --prompt "Sway Keys:" --width $width
  exit
}

# Großes Overlay
echo "$keybinds" | fuzzel \
  --dmenu \
  --prompt "Sway Keys:" \
  --width $width \
  --lines 20
