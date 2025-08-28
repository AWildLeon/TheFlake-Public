_:

{
  home-manager.sharedModules = [
    (
      { lib, config, ... }:
      {
        stylix.targets.vscode.enable = false;

        # Alte Datei vor dem Verlinken entfernen, damit Stylix sauber symlinkt
        home.activation.nukeGtkrc = lib.hm.dag.entryBefore [ "checkLinkTargets" "linkGeneration" ] ''
          rm -f "${config.home.homeDirectory}/.gtkrc-2.0"
        '';
      }
    )
  ];
}
