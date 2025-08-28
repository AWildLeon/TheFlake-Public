{
  nixConfig = {
    substituters =
      [ "https://cache.nixos.org/" "https://nix-community.cachix.org" ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
  };

  inputs = {
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence.url = "github:nix-community/impermanence";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    colmena.url = "github:zhaofengli/colmena";

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixos-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    arion = {
      url = "github:AWildLeon/leons-arion/prod";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";

    stylix = {
      url = "github:nix-community/stylix/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix4vscode = {
      url = "github:nix-community/nix4vscode";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, colmena, disko, impermanence
    , nixos-generators, nixos-unstable, home-manager, plasma-manager, agenix
    , treefmt-nix, arion, nixos-facter-modules, stylix, spicetify-nix
    , pre-commit-hooks, nix4vscode, ... }:
    let
      ts = builtins.toString
        (self.lastModified or (inputs.nixpkgs.lastModified or 0));

      # System configurations
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forEachSystem = nixpkgs.lib.genAttrs supportedSystems;

      # Pre-commit hooks configuration
      pre-commit-check = forEachSystem (system:
        pre-commit-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            treefmt.enable = true;
            deadnix.enable = true;
            statix.enable = true;
            nixpkgs-fmt.enable = true;
            shellcheck.enable = true;
          };
        });

      commonSpecialArgs = {
        inherit disko impermanence home-manager nixos-unstable agenix arion
          nixos-facter-modules nixos-generators ts stylix spicetify-nix
          nix4vscode plasma-manager;
      };

      # Helper functions for creating system configurations
      lib = {
        # Helper function to create a NixOS system configuration
        mkNixosSystem = { system ? "x86_64-linux", hostname, modules ? [ ]
          , extraSpecialArgs ? { }, withUnstable ? true, withHomeManager ? false
          , withDisko ? false, withImpermanence ? false, }:
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
              # Base configuration path
              ./machines/${hostname}/configuration.nix
            ] ++ (nixpkgs.lib.optionals withDisko [ disko.nixosModules.disko ])
              ++ (nixpkgs.lib.optionals withImpermanence
                [ impermanence.nixosModules.impermanence ])
              ++ (nixpkgs.lib.optionals withHomeManager
                [ home-manager.nixosModules.home-manager ]) ++ modules;
          };

        # Helper function to create a Colmena deployment configuration
        mkColmenaDeployment = { hostname, targetHost, targetPort ? 22
          , targetUser ? "root", tags ? [ "server" ], modules ? [ ]
          , withDisko ? false, withImpermanence ? false, }: {
            deployment = { inherit targetHost targetPort targetUser tags; };
            imports = [ ./machines/${hostname}/configuration.nix ]
              ++ (nixpkgs.lib.optionals withDisko [ disko.nixosModules.disko ])
              ++ (nixpkgs.lib.optionals withImpermanence
                [ impermanence.nixosModules.impermanence ]) ++ modules;
          };

        # Helper function to create a VM template configuration
        mkVmTemplate = { system ? "x86_64-linux", modules ? [ ]
          , withDocker ? false, diskDevice ? "vda", withUnstable ? false, }:
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
              impermanence.nixosModules.impermanence
              ./nixos-anywhere/${
                if withDocker then
                  "base-docker"
                else if diskDevice == "sda" then
                  "base-sda"
                else
                  "base"
              }/configuration.nix
              ./nixos-anywhere/${
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
          { format, system ? "x86_64-linux", modules ? [ ], diskSize ? null, }:
          nixos-generators.nixosGenerate {
            inherit system format;
            specialArgs = commonSpecialArgs;
            modules = [
              ({ lib, ... }:
                {
                  nix.registry.nixpkgs.flake = nixpkgs;
                } // lib.optionalAttrs (diskSize != null) {
                  virtualisation.diskSize = diskSize;
                })
            ] ++ modules;
          };
      };

    in {
      # Export helper functions for external use
      inherit lib;

      # Pre-commit checks
      checks = forEachSystem
        (system: { pre-commit-check = pre-commit-check.${system}; });

      colmenaHive = colmena.lib.makeHive {
        meta = {
          nixpkgs = import nixpkgs {
            system = "x86_64-linux";
            overlays = [ ];
          };
          specialArgs = commonSpecialArgs // {
            pkgsUnstable = import nixos-unstable {
              system = "x86_64-linux";
              config.allowUnfree = true;
            };
            inherit colmena;
          };
        };
        # ... Machines Omitted for Privacy ...
      };

      nixosConfigurations = {
        # ... Machines Omitted for Privacy ...
      };

      # Treefmt configuration
      treefmt = treefmt-nix.lib.evalModule nixpkgs.legacyPackages.x86_64-linux {
        projectRootFile = "flake.nix";
        programs = {
          nixpkgs-fmt.enable = true;
          prettier = {
            enable = true;
            includes = [ "*.md" "*.yaml" "*.yml" "*.json" ];
          };
          shfmt = {
            enable = true;
            indent_size = 2;
          };
        };
        settings.global.excludes = [
          # Exclude shell scripts from shellcheck for now due to configuration issues
          "*.sh"
        ];
      };

      # Development shell
      devShells = forEachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          theme_omz = builtins.fetchurl {
            url = "https://zsh.onlh.de/theme.omp.json";
            sha256 = "1jd355hilldj4ncf0h28n70qwx43zddzn5xdxamc2y6dmlmxh79c";
          };
        in {
          default = pkgs.mkShell {
            buildInputs = pre-commit-check.${system}.enabledPackages;
            packages = with pkgs; [
              # Treefmt for formatting
              self.treefmt.config.build.wrapper

              # Development tools
              nixfmt-classic
              shellcheck
              shfmt
              nodePackages.prettier
              deadnix
              statix

              # Deployment tools
              colmena.packages.${system}.colmena
              agenix.packages.${system}.default

              # Git hooks
              git

              # Shell tools
              zsh
              fastfetchMinimal
              oh-my-posh
              zoxide

              # Additional development utilities
              nix-output-monitor
              nix-tree
              nixos-rebuild
            ];

            shellHook = pre-commit-check.${system}.shellHook + ''
              # Initialize zoxide with cd alias
              eval "$(zoxide init --cmd cd bash)"

              # Initialize oh-my-posh with your theme
              eval "$(oh-my-posh init bash --config "${theme_omz}")"

              # Show system info
              fastfetch

              echo ""
              echo "🏗️  NixOS Configs Development Shell"
              echo ""
              echo "📋 Available commands:"
              echo "  treefmt                    - Format all files"
              echo "  deadnix                    - Find dead Nix code"
              echo "  statix                     - Nix linter"
              echo ""
              echo "🚀 Deployment commands:"
              echo "  colmena apply              - Deploy all machines"
              echo "  colmena apply --dry-run    - Preview deployment"
              echo "  colmena build              - Build configurations"
              echo "  agenix                     - Manage secrets"
              echo ""
            '';
          };
        });

      # Format all files command
      apps.x86_64-linux = {
        treefmt = {
          type = "app";
          program = "${self.treefmt.config.build.wrapper}/bin/treefmt";
        };

        # Deployment scripts
        deploy = {
          type = "app";
          program = toString
            (nixpkgs.legacyPackages.x86_64-linux.writeScript "deploy" ''
              #!/usr/bin/env bash
              set -e
              echo "🚀 Deploying all machines with Colmena..."
              ${colmena.packages.x86_64-linux.colmena}/bin/colmena apply
            '');
        };

        deploy-dry-run = {
          type = "app";
          program = toString
            (nixpkgs.legacyPackages.x86_64-linux.writeScript "deploy-dry-run" ''
              #!/usr/bin/env bash
              set -e
              echo "🔍 Running deployment dry-run..."
              ${colmena.packages.x86_64-linux.colmena}/bin/colmena apply --dry-run
            '');
        };

        build-all = {
          type = "app";
          program = toString
            (nixpkgs.legacyPackages.x86_64-linux.writeScript "build-all" ''
              #!/usr/bin/env bash
              set -e
              echo "🔨 Building all configurations..."
              ${colmena.packages.x86_64-linux.colmena}/bin/colmena build
            '');
        };

        check-secrets = {
          type = "app";
          program = toString
            (nixpkgs.legacyPackages.x86_64-linux.writeScript "check-secrets" ''
              #!/usr/bin/env bash
              set -e
              echo "🔐 Checking secrets with agenix..."
              ${agenix.packages.x86_64-linux.default}/bin/agenix -i ./secrets/secrets.nix
            '');
        };
      };

    };

}
