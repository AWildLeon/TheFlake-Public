{ lib, config, home-manager ? null, ... }:

with lib;

let
  cfg = config.lh.cosmetic.stylix-home-manager;
in
{
  options.lh.cosmetic.stylix-home-manager = {
    enable = mkEnableOption "Enable Stylix home-manager integration and workarounds";

    disableVSCodeStylix = mkOption {
      type = types.bool;
      default = true;
      description = "Disable Stylix theming for VSCode";
    };

    enableGtkrcWorkaround = mkOption {
      type = types.bool;
      default = true;
      description = "Enable GTK RC file cleanup workaround for Stylix";
    };
  };

  config = mkIf cfg.enable {
    home-manager.sharedModules = [
      (
        { lib, config, ... }:
        {
          stylix.targets.vscode.enable = lib.mkForce false;

          # Alte Datei vor dem Verlinken entfernen, damit Stylix sauber symlinkt
          home.activation.nukeGtkrc = mkIf cfg.enableGtkrcWorkaround (lib.hm.dag.entryBefore [ "checkLinkTargets" "linkGeneration" ] ''
            rm -f "${config.home.homeDirectory}/.gtkrc-2.0"
          '');
        }
      )
    ];
  };
}
