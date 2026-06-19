{
  perSystem =
    { pkgs, lib, ... }:
    let
      hmSwitch = pkgs.writeShellApplication {
        name = "hm-switch";
        runtimeInputs = [
          pkgs.nix
          pkgs.fzf
          pkgs.bash
        ];
        text = ''
          exec bash ${./switch.sh} "$@"
        '';
      };
    in
    {
      packages.hm-switch = hmSwitch;

      apps.hm-switch = {
        type = "app";
        program = lib.getExe hmSwitch;
      };
    };
}
