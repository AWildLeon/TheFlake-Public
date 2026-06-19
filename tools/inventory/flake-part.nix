{
  perSystem =
    { pkgs, lib, ... }:
    let
      discoverSshKeys = pkgs.writeShellApplication {
        name = "discover-ssh-keys";
        runtimeInputs = [
          pkgs.git
          pkgs.nix
          pkgs.openssh
          pkgs.python3
        ];
        text = ''
          exec python3 ${./discover-ssh-ed25519-keys.py} "$@"
        '';
      };
    in
    {
      packages.discover-ssh-keys = discoverSshKeys;

      apps.discover-ssh-keys = {
        type = "app";
        program = lib.getExe discoverSshKeys;
      };
    };
}
