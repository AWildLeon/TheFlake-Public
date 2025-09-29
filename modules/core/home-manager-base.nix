{ home-manager
, ts
, nix4vscode
, pkgsUnstable
, ...
}:
{
  imports = [
    home-manager.nixosModules.home-manager
  ];

  # Add nix4vscode overlay to system-wide nixpkgs
  nixpkgs.overlays = [
    nix4vscode.overlays.default
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-bak-${ts}";
    extraSpecialArgs = {
      inherit nix4vscode pkgsUnstable;
    };
  };
}
