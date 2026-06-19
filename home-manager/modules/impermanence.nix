{
  lib,
  config,
  options,
  osConfig ? null,
  ...
}:
let
  cfg = config.lh.home.impermanence;
  haveHomePersistence = options ? home && options.home ? persistence;
  osCfg =
    if
      osConfig != null && osConfig ? lh && osConfig.lh ? system && osConfig.lh.system ? impermanence
    then
      osConfig.lh.system.impermanence
    else
      {
        enable = false;
        persistentPath = "/persistent";
      };
in
{

  options.lh.home.impermanence = {
    enable = lib.mkEnableOption "Enable impermanence for Home Manager";

    persistentDirectories = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.str lib.types.attrs);
      default = [ ];
      description = "Directories to persist across reboots";
      apply = lib.lists.unique;
    };

    persistentFiles = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.str lib.types.attrs);
      default = [ ];
      description = "Files to persist across reboots";
    };
  };

  config = lib.optionalAttrs haveHomePersistence (
    lib.mkIf (osCfg.enable && cfg.enable) {

      lh.home.impermanence = {
        persistentDirectories = [
          "Downloads"
          "Dokumente"
          "Bilder"
          "Musik"
          "Videos"
          "workspace"
          ".cache"
          ".local/state"
          ".config/Signal"
          ".config/Code"

          {
            directory = ".local/share/kwalletd";
            mode = "0700";
          }
          {
            directory = ".local/share/klipper";
            mode = "0700";
          }
          {
            directory = ".config/kdeconnect";
            mode = "0700";
          }

          ".vscode"
          {
            directory = ".config/BraveSoftware";
            mode = "0700";
          }
          {
            directory = ".local/share/keyrings";
            mode = "0700";
          }
          {
            directory = ".ssh";
            mode = "0700";
          }
          ".local/share/direnv"
        ];
        persistentFiles = [
          ".zsh_history"
          ".zshrc"
          ".config/kwinoutputconfig.json"
          ".config/plasma-org.kde.plasma.desktop-appletsrc"
          ".config/plasmashellrc"
          ".config/konsolerc"
          {
            file = ".config/kwinrc";
            method = "symlink";
          }
          ".config/kwalletrc"
          ".config/mimeapps.list"
        ];
      };

      home.persistence.${osCfg.persistentPath} = {
        directories = cfg.persistentDirectories;
        files = cfg.persistentFiles;
      };
    }
  );
}
