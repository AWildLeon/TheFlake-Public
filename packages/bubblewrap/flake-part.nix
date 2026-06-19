{
  inputs,
  lib,
  ...
}:
let
  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];

  unfreePkgs =
    pkg:
    builtins.elem (lib.getName pkg) [
      "discord"
      "spotify"
    ];

  mkPkgs =
    system:
    import inputs.nixpkgs {
      inherit system;
      config.allowUnfreePredicate = unfreePkgs;
    };

  llmPackageFiles = {
    claude = ./llm/claude.nix;
    codex = ./llm/codex.nix;
    gemini = ./llm/gemini.nix;
    pi = ./llm/pi.nix;
  };

  guiPackageFiles = {
    discord = ./discord.nix;
    spotify = ./spotify.nix;
  };

  mkBubblewrappedPackages =
    system:
    let
      pkgs = mkPkgs system;
      pkgsUnstable = import inputs.nixos-unstable { inherit system; };
      llm = inputs.llm-agents.packages.${system};

      mkNixPak = inputs.nixpak.lib.nixpak {
        inherit (pkgs) lib;
        inherit pkgs;
      };

      mkLlmTool = import ./llm/mk-llm-tool.nix {
        inherit
          inputs
          system
          pkgs
          pkgsUnstable
          mkNixPak
          ;
      };

      mkGuiApp = import ./mk-gui-app.nix {
        inherit inputs pkgs mkNixPak;
      };

      callLlmPackage = file: import file { inherit llm mkLlmTool; };
      callGuiPackage = file: import file { inherit pkgs mkGuiApp; };
    in
    lib.optionalAttrs (system == "x86_64-linux") (lib.mapAttrs (_: callGuiPackage) guiPackageFiles)
    // {
      llm = lib.mapAttrs (_: callLlmPackage) llmPackageFiles;
    };
in
{
  flake.packages = lib.genAttrs systems (system: {
    bubblewrapped =
      let
        pkgs = mkPkgs system;
      in
      pkgs.runCommand "bubblewrapped-packages"
        {
          passthru = mkBubblewrappedPackages system;
        }
        ''
          mkdir -p $out
        '';
  });
}
