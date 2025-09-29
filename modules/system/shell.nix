{ pkgs, config, lib, self, ... }:

let
  theme_omz = builtins.fetchurl {
    url = "https://zsh.onlh.de/theme.omp.json";
    sha256 = "1jd355hilldj4ncf0h28n70qwx43zddzn5xdxamc2y6dmlmxh79c";
  };
  LHFastfetchLogo =
    builtins.path { path = self + "/resources/logo_fastfetch.ansi"; };
  lhShellTools = pkgs.stdenv.mkDerivation {
    pname = "lh-shell-tools";
    version = "1.0";
    src = ./shell-tools;

    # If your repo preserves +x, you can skip chmod and just use install -Dm755.
    installPhase = ''
      mkdir -p $out/bin
      # take only regular files in the root of src; adjust as needed
      for f in "$src"/*; do
        [ -f "$f" ] || continue
        install -Dm755 "$f" "$out/bin/$(basename "$f")"
      done
    '';
  };
in
{
  options.lh.system.shell = {
    enable = lib.mkEnableOption
      "Enable Zsh as the default shell with Oh My Zsh and enhancements.";
    LHLogo = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description =
        "Whether to show the LH Logo in the terminal prompt instead of the NixOS logo.";
    };
  };

  config = lib.mkIf config.lh.system.shell.enable {
    programs.zsh = {
      enable = true;
      enableBashCompletion = true;
      shellAliases = {
        # General
        #ll = "eza -la --group-directories-first --icons always";
        #l = "eza -l --icons always";
        #la = "eza -a --icons always";
        #ls = "eza --icons always";
        "cd.." = "cd ..";
      };
      interactiveShellInit =
        if config.lh.system.shell.LHLogo then ''
          fastfetch -l "${LHFastfetchLogo}"
        '' else ''
          fastfetch
        '';
      ohMyZsh = {
        enable = true;
        plugins = [ "git" "sudo" "docker" "docker-compose" ];
        #"eza"
      };
      vteIntegration = true;

      promptInit = ''
        eval "$(oh-my-posh init zsh --config "${theme_omz}")"
      '';

    };

    users.defaultUserShell = pkgs.zsh;
    environment.systemPackages = with pkgs; [
      fastfetchMinimal
      oh-my-posh
      eza
      lhShellTools
    ];

    programs.zoxide = {
      enable = true;
      flags = [ "--cmd cd" ];
    };
  };
}
