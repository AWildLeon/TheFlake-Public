# System configuration helpers
{ inputs, self }:
let
  inherit (inputs)
    nixpkgs nixos-unstable disko impermanence home-manager nixos-generators
    agenix arion nixos-facter-modules stylix spicetify-nix nix4vscode
    plasma-manager glance-ical-events colmena nix-flatpak copyparty;
  hostDiscovery = import ./host-discovery.nix { inherit inputs self; };

  ts =
    builtins.toString (self.lastModified or (inputs.nixpkgs.lastModified or 0));

  commonSpecialArgs = {
    inherit disko impermanence home-manager nixos-unstable agenix arion
      nixos-facter-modules nixos-generators stylix spicetify-nix nix4vscode
      plasma-manager glance-ical-events ts self nix-flatpak copyparty;
    # Make colmena package available where needed
    inherit (colmena.packages.x86_64-linux) colmena;
    # Provide flake lib for path helpers
    flakeLib = import ../lib { inherit inputs self; };
  };

  # Helper function to create a NixOS system configuration
  mkNixosSystem =
    { system ? "x86_64-linux"
    , hostname
    , modules ? [ ]
    , extraSpecialArgs ? { }
    , withUnstable ? true
    , withHomeManager ? true
    , withDisko ? false
    , withImpermanence ? false
    , withStylix ? true
    , withNixFlatpak ? false
    }:
    nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = commonSpecialArgs // extraSpecialArgs
        // (nixpkgs.lib.optionalAttrs withUnstable {
        pkgsUnstable = import nixos-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      });
      modules = [
        # Set the hostname
        {
          networking.hostName = nixpkgs.lib.mkDefault hostname;
        }
        (hostDiscovery.machineConfig hostname)
      ] ++ (nixpkgs.lib.optionals withDisko [ disko.nixosModules.disko ])
      ++ (nixpkgs.lib.optionals withImpermanence
        [ impermanence.nixosModules.impermanence ])
      ++ (nixpkgs.lib.optionals withStylix
        [ stylix.nixosModules.stylix ])
      ++ (nixpkgs.lib.optionals withNixFlatpak
        [ nix-flatpak.nixosModules.nix-flatpak ])
      ++ (nixpkgs.lib.optionals withHomeManager
        [ home-manager.nixosModules.home-manager ]) ++ modules;
    };

in
{
  inherit mkNixosSystem;

  # Helper function to create a VM template configuration
  mkVmTemplate =
    { system ? "x86_64-linux"
    , modules ? [ ]
    , withDocker ? false
    , diskDevice ? "vda"
    , withUnstable ? false
    }:
    nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = commonSpecialArgs
        // (nixpkgs.lib.optionalAttrs withUnstable {
        pkgsUnstable = import nixos-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      });
      modules = [
        disko.nixosModules.disko
        stylix.nixosModules.stylix
        impermanence.nixosModules.impermanence
        ../nixos-anywhere/${
          if withDocker then
            "base-docker"
          else if diskDevice == "sda" then
            "base-sda"
          else
            "base"
        }/configuration.nix
        ../nixos-anywhere/${
          if withDocker then
            "base-docker"
          else if diskDevice == "sda" then
            "base-sda"
          else
            "base"
        }/hardware-configuration.nix


      ] ++ modules;
    };

  # Helper function to create a generator package
  mkGenerator =
    { format
    , system ? "x86_64-linux"
    , modules ? [ ]
    , diskSize ? null
    , withStylix ? true
    }:
    nixos-generators.nixosGenerate {
      inherit system format;
      specialArgs = commonSpecialArgs;
      modules = [
        (
          { lib, ... }:
          {
            nix.registry.nixpkgs.flake = nixpkgs;
          }
          // lib.optionalAttrs (diskSize != null) {
            virtualisation.diskSize = diskSize;
          }
        )
      ]
      ++ (nixpkgs.lib.optionals withStylix [
        stylix.nixosModules.stylix
      ])
      ++ modules;
    };

  # Auto-generated NixOS configurations from discovered hosts
  mkNixosAuto = builtins.listToAttrs (builtins.map
    (h:
      let
        hostVars = hostDiscovery.loadHostVars h;
        deployConfig = hostVars.deployment or { };
      in
      {
        name = h;
        value = mkNixosSystem {
          hostname = h;
          # Apply deployment flags from vars.nix
          withDisko = deployConfig.withDisko or false;
          withImpermanence = deployConfig.withImpermanence or false;
          withHomeManager = deployConfig.withHomeManager or true;
          withUnstable = deployConfig.withUnstable or true;
          withStylix = deployConfig.withStylix or true;
          withNixFlatpak = deployConfig.withNixFlatpak or false;
          # Pass hostVars as extraSpecialArgs so configs can access them
          extraSpecialArgs = { inherit hostVars; };
        };
      })
    hostDiscovery.hosts);
}
