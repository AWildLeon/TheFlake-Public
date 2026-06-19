_:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      packetCourt = pkgs.writeShellApplication {
        name = "packet-court";
        runtimeInputs = [
          pkgs.python3
          pkgs.nix
          pkgs.git
        ];
        text = ''
          if git rev-parse --show-toplevel > /dev/null 2>&1; then
            FLAKE_ROOT="$(git rev-parse --show-toplevel)"
          else
            FLAKE_ROOT="$PWD"
          fi

          exec ${pkgs.python3}/bin/python "$FLAKE_ROOT/tools/packet/packet_court.py" \
            --flake "$FLAKE_ROOT" \
            "$@"
        '';
      };

      packetCourtTests = pkgs.runCommand "packet-court-tests" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        cd ${../..}
        ${pkgs.python3}/bin/python tools/packet/tests.py
        touch $out
      '';
    in
    {
      packages.packet-court = packetCourt;
      apps.packet = {
        type = "app";
        program = lib.getExe packetCourt;
      };
      checks.packet-court = packetCourtTests;
    };
}
