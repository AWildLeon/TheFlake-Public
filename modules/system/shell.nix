{ pkgs, ... }:

let
  theme_omz = builtins.fetchurl {
    url = "https://zsh.onlh.de/theme.omp.json";
    sha256 = "1jd355hilldj4ncf0h28n70qwx43zddzn5xdxamc2y6dmlmxh79c";
  };
in
{
  programs.zsh = {
    enable = true;
    enableBashCompletion = true;
    interactiveShellInit = ''
      fastfetch
    '';
    ohMyZsh = {
      enable = true;
      plugins = [
        "git"
        "sudo"
        "docker"
        "docker-compose"
      ];
    };

    promptInit = ''
      eval "$(oh-my-posh init zsh --config "${theme_omz}")"
    '';

  };

  users.defaultUserShell = pkgs.zsh;
  environment.systemPackages = with pkgs; [
    fastfetchMinimal
    oh-my-posh
  ];

  programs.zoxide = {
    enable = true;
    flags = [
      "--cmd cd"
    ];
  };
}
