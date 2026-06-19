#!/usr/bin/env bash
ip_file=./ip-vm-nixos

if [[ ! -f $ip_file ]]; then
  echo "❌ IP-Datei fehlt."
  exit 1
fi

IP=$(<$ip_file)
if [[ -z $IP ]]; then
  echo "❌ IP-Datei ist leer."
  exit 1
fi
rm $ip_file

cd "$HOME/nix-configs" || exit 1

nixos-anywhere --target-host "$IP" --ssh-option "StrictHostKeyChecking=no" \
  --ssh-option "UserKnownHostsFile=/dev/null" \
  --ssh-option "ConnectTimeout=10" \
  --ssh-option "ServerAliveInterval=60" \
  --ssh-option "ServerAliveCountMax=3" \
  --phases disko,install \
  --flake .#templates.base-vm &>/dev/stdout
