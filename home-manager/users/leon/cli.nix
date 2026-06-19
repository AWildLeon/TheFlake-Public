_: {
  imports = [
    ../../profiles/cli/nix-dev.nix
    ../../profiles/cli/zsh.nix
    ./cli/git.nix
    ./cli/ssh.nix
  ];

  home = {
    homeDirectory = "/home/leon";
    stateVersion = "25.11";
    username = "leon";
  };
  nixpkgs.config.allowUnfree = true;
}
