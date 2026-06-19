{ inputs, pkgs, ... }: {
  imports = [
    inputs.lhzsh.homeManagerModules.default
  ];

  config = {
    programs = {
      lhzsh = {
        enable = true;
      };
    };
    home.sessionVariables = {
      SHELL = "${pkgs.zsh}/bin/zsh";
    };
  };
}
