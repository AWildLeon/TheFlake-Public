# App definitions for nix run
{ inputs, self }:
let
  inherit (inputs) nixpkgs colmena agenix;
in
{
  mkApps = {
    # Format all files command
    treefmt = {
      type = "app";
      program = "${self.treefmt.config.build.wrapper}/bin/treefmt";
      meta = {
        description = "Format all files using treefmt";
      };
    };

    # Deployment scripts
    deploy = {
      type = "app";
      program = toString (
        nixpkgs.legacyPackages.x86_64-linux.writeScript "deploy" ''
          #!/usr/bin/env bash
          set -e
          echo "🚀 Deploying all machines with Colmena..."
          ${colmena.packages.x86_64-linux.colmena}/bin/colmena apply
        ''
      );
      meta = {
        description = "Deploy all machines with Colmena";
      };
    };

    deploy-dry-run = {
      type = "app";
      program = toString (
        nixpkgs.legacyPackages.x86_64-linux.writeScript "deploy-dry-run" ''
          #!/usr/bin/env bash
          set -e
          echo "🔍 Running deployment dry-run..."
          ${colmena.packages.x86_64-linux.colmena}/bin/colmena apply --dry-run
        ''
      );
      meta = {
        description = "Run deployment dry-run with Colmena";
      };
    };

    build-all = {
      type = "app";
      program = toString (
        nixpkgs.legacyPackages.x86_64-linux.writeScript "build-all" ''
          #!/usr/bin/env bash
          set -e
          echo "🔨 Building all configurations..."
          ${colmena.packages.x86_64-linux.colmena}/bin/colmena build
        ''
      );
      meta = {
        description = "Build all configurations with Colmena";
      };
    };

    check-secrets = {
      type = "app";
      program = toString (
        nixpkgs.legacyPackages.x86_64-linux.writeScript "check-secrets" ''
          #!/usr/bin/env bash
          set -e
          echo "🔐 Checking secrets with agenix..."
          ${agenix.packages.x86_64-linux.default}/bin/agenix -i ./secrets/secrets.nix
        ''
      );
      meta = {
        description = "Check secrets with agenix";
      };
    };
  };
}
