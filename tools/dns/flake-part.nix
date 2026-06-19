{
  perSystem =
    { pkgs, lib, ... }:
    let
      technitiumZoneSync = pkgs.writeShellApplication {
        name = "technitium-zone-sync";
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

          cd "$FLAKE_ROOT"

          if [[ ! -f "tools/dns/technitium_zone_sync.py" ]]; then
             echo "Error: tools/dns/technitium_zone_sync.py not found. Please run from the flake root."
             exit 1
          fi

          exec python3 tools/dns/technitium_zone_sync.py "$@"
        '';
      };
    in
    {
      packages.technitium-zone-sync = technitiumZoneSync;

      apps.technitium-zone-sync = {
        type = "app";
        program = lib.getExe technitiumZoneSync;
      };
    };
}
