{ inputs, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      python = pkgs.python3.withPackages (
        ps: with ps; [
          proxmoxer
          requests
          prompt-toolkit
        ]
      );

      proxmoxSync = pkgs.writeShellApplication {
        name = "proxmox-sync";
        runtimeInputs = [
          python
          pkgs.nix
          pkgs.git
          pkgs.openssh
          inputs.colmena.packages.${pkgs.stdenv.hostPlatform.system}.colmena
        ];
        text = ''
          if git rev-parse --show-toplevel > /dev/null 2>&1; then
            FLAKE_ROOT="$(git rev-parse --show-toplevel)"
          else
            FLAKE_ROOT="$PWD"
          fi

          exec python3 "$FLAKE_ROOT/tools/proxmox/sync.py" \
            --flake-root "$FLAKE_ROOT" \
            "$@"
        '';
      };
    in
    {
      packages.proxmox-sync = proxmoxSync;

      apps.proxmox-sync = {
        type = "app";
        program = lib.getExe proxmoxSync;
      };
    };
}
