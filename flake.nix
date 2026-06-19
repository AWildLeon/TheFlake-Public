{
  description = "My NixOS configuration flake";

  nixConfig = {
    substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org"
      "https://awildleon-nixlib.cachix.org"
      "https://cache.numtide.com"
    ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "awildleon-nixlib.cachix.org-1:jDsApfkbRWepIRrxDVVFUJHQLuAgliX0WTicUnTs9rI="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  inputs = {
    lh-nixlib = {
      url = "github:awildleon/lh-nixlib";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixos-unstable";
    };

    lhzsh = {
      url = "github:AWildLeon/lhzsh";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };

    nixpak = {
      url = "github:nixpak/nixpak";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dns = {
      url = "github:nix-community/dns.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs."home-manager".follows = "home-manager";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    colmena.url = "github:zhaofengli/colmena";

    nixpkgs.follows = "lh-nixlib/nixpkgs";
    nixos-unstable.follows = "lh-nixlib/nixos-unstable";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    glance-ical-events = {
      url = "github:AWildLeon/Glance-iCal-Events";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:nix-community/stylix/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix4vscode = {
      url = "github:nix-community/nix4vscode";
      inputs.nixpkgs.follows = "nixos-unstable";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
    };

    nuschtosSearch = {
      url = "github:NuschtOS/search";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    notnft = {
      url = "github:chayleaf/notnft";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    inputs@{ flake-parts, ... }:
    # https://flake.parts/module-arguments.html
    flake-parts.lib.mkFlake { inherit inputs; } (
      {
        self,
        ...
      }:
      {
        perSystem =
          {
            lib,
            system,
            ...
          }:
          let
            # Flake/devShell scope only (devShells, packages, apps, checks).
            # NixOS hosts get their own `pkgs`/`pkgsUnstable` from
            # profiles/hosts/defaults/default.nix, which allows unfree broadly
            # (hosts pull unfree pkgs like vscode/jetbrains). Here we keep the
            # allowance narrow — just the unfree CLI tools the devShell needs.
            unfreePkgs =
              pkg:
              builtins.elem (lib.getName pkg) [
                "terraform"
                "packer"
              ];
          in
          {
            _module.args.pkgs = import self.inputs.nixpkgs {
              inherit system;
              config.allowUnfreePredicate = unfreePkgs;
            };
            _module.args.pkgsUnstable = import self.inputs.nixos-unstable {
              inherit system;
              config.allowUnfreePredicate = unfreePkgs;
            };
          };

        imports = [
          ./lib/flake-part.nix
          ./dns/dns-inventory.nix
          ./dns/flake-part.nix
          ./disko/flake-part.nix
          ./modules/flake-part.nix
          ./home-manager/flake-part.nix
          ./profiles/flake-part.nix
          ./packer/flake-part.nix
          ./proxmox/flake-part.nix
          ./tools/ai/flake-part.nix
          ./tools/dns/flake-part.nix
          ./tools/inventory/flake-part.nix
          ./tools/proxmox/flake-part.nix
          ./tools/packet/flake-part.nix
          ./tools/lhflake/flake-part.nix
          ./tools/homemanager/flake-part.nix
          ./parts/inventory.nix
          ./parts/options-search.nix
          ./parts/treefmt.nix
          ./packages/bubblewrap/flake-part.nix
          ./parts/nix-develop.nix
          ./nftables/flake-part.nix

          inputs.disko.flakeModules.default
          inputs.treefmt-nix.flakeModule
          inputs.home-manager.flakeModules.home-manager
        ];
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];
      }
    );
}
