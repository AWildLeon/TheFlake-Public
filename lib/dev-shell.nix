# Development shell configuration
{ inputs, self }:
let
  inherit (inputs) nixpkgs pre-commit-hooks agenix colmena;
  supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
  forEachSystem = nixpkgs.lib.genAttrs supportedSystems;

  # Pre-commit hooks configuration
  pre-commit-check = forEachSystem (
    system:
    pre-commit-hooks.lib.${system}.run {
      src = self;
      hooks = {
        treefmt.enable = true;
        deadnix.enable = true;
        statix.enable = true;
        nixpkgs-fmt.enable = true;
        shellcheck.enable = true;
      };
    }
  );

in
{
  inherit pre-commit-check;

  mkDevShells = forEachSystem (
    system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      theme_omz = builtins.fetchurl {
        url = "https://zsh.onlh.de/theme.omp.json";
        sha256 = "1jd355hilldj4ncf0h28n70qwx43zddzn5xdxamc2y6dmlmxh79c";
      };
    in
    {
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
          inotify-tools

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
          echo "  treefmt --fail-on-change   - Check if files are formatted"
          echo "  deadnix                    - Find dead Nix code"
          echo "  statix                     - Nix linter"
          echo ""
          echo "🚀 Deployment commands:"
          echo "  colmena apply              - Deploy all machines"
          echo "  colmena apply --dry-run    - Preview deployment"
          echo "  colmena build              - Build configurations"
          echo "  agenix                     - Manage secrets"
          echo ""
          echo "🔧 System commands:"
          echo "  nixos-rebuild              - Rebuild local system"
          echo "  nix-output-monitor         - Pretty nix build output"
          echo "  nix-tree                   - Explore dependency tree"
          echo ""
        '';
      };
    }
  );
}
