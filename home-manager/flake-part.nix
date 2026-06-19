{
  inputs,
  lib,
  ...
}:
let
  homeLib = import ./lib {
    inherit lib;
    inherit (inputs) self;
  };

  leonCli = import ./users/leon/cli.nix;
  leonDesktop = import ./users/leon/desktop.nix;
  leonDesktopNoVscode = import ./users/leon/desktop-novscode.nix;

  standaloneSystem = builtins.currentSystem or "x86_64-linux";

  mkUser =
    {
      module,
      genericLinux ? false,
    }:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = inputs.self.lh.lib.pkgsFor.${standaloneSystem};

      extraSpecialArgs = {
        inherit inputs;
        inherit (inputs.self) lh;
        pkgsUnstable = inputs.self.lh.lib.pkgsUnstableFor.${standaloneSystem};
      };

      modules = [
        inputs.stylix.homeModules.stylix
        inputs.self.homeModules.default
        module
        {
          targets.genericLinux.enable = genericLinux;
        }
      ];
    };
in
{
  flake = {
    homeConfigurations = {
      leon-cli = mkUser { module = leonCli; };
      leon-desktop = mkUser { module = leonDesktop; };
      leon-desktop-novscode = mkUser { module = leonDesktopNoVscode; };
      generic-leon-cli = mkUser {
        module = leonCli;
        genericLinux = true;
      };
      generic-leon-desktop = mkUser {
        module = leonDesktop;
        genericLinux = true;
      };
      generic-leon-desktop-novscode = mkUser {
        module = leonDesktopNoVscode;
        genericLinux = true;
      };
    };

    lh.lib.home = homeLib;

    homeModules = rec {
      impermanence = import ./modules/impermanence.nix;

      profile_cli_nix-dev = import ./profiles/cli/nix-dev.nix;
      profile_desktop_apps = import ./profiles/desktop/apps.nix;
      profile_desktop_kde-sycoca = import ./profiles/desktop/kde-sycoca.nix;
      profile_desktop_browser = import ./profiles/desktop/browser.nix;
      profile_desktop_ssh-agent = import ./profiles/desktop/ssh-agent.nix;

      default = {
        imports = [ impermanence ];
      };
    };
  };
}
