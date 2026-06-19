{
  pkgs,
  config,
  lib,
  ...
}:

let
  lhShellTools = pkgs.stdenv.mkDerivation {
    pname = "lh-shell-tools";
    version = "1.0";
    src = ./shell-tools;

    installPhase = ''
      mkdir -p $out/bin
      for f in "$src"/*; do
        [ -f "$f" ] || continue
        install -Dm755 "$f" "$out/bin/$(basename "$f")"
      done
    '';
  };
in
{
  options.lh.system.shell = {
    enable = lib.mkEnableOption "LHZSH shell setup.";
  };

  config = lib.mkIf config.lh.system.shell.enable {
    programs.lhzsh.enable = true;

    programs.zsh = {
      enableBashCompletion = true;
      vteIntegration = true;
    };

    users.defaultUserShell = pkgs.zsh;

    environment.systemPackages = with pkgs; [
      fastfetch.minimal
      eza
      direnv
      lhShellTools

      htop
      btop
      bmon
      nmap
      lsof
      tcpdump
      dig
    ];

    programs.zoxide = {
      enable = true;
      enableZshIntegration = false;
      flags = [ "--cmd cd" ];
    };
  };
}
