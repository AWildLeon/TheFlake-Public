{ pkgs, ... }:
{
  imports = [
    ./base.nix
    ../../modules/system/fhs-compat.nix
  ];

  # Development and deployment tools (colmena added per-machine)
  environment.systemPackages = with pkgs; [
    nixfmt-classic
    packer
    pipx
    ansible-lint
    nixos-anywhere
    nil
    nodejs
  ];

  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    trusted-users = [
      "root"
      "leon"
    ];
  };

  networking.firewall.enable = false;
}
