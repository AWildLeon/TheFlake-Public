{
  perSystem =
    {
      pkgs,
      pkgsUnstable,
      lib,
      ...
    }:
    let
      python = pkgs.python3.withPackages (ps: [ ps.fastmcp ]);

      pi-nixos-mcp = pkgs.writeShellApplication {
        name = "pi-nixos-mcp";
        runtimeInputs = [
          python
          pkgsUnstable.mcp-nixos
        ];
        text = ''
          exec python3 ${./pi_nixos_mcp.py} "$@"
        '';
      };
    in
    {
      packages.pi-nixos-mcp = pi-nixos-mcp;

      apps.pi-nixos-mcp = {
        type = "app";
        program = lib.getExe pi-nixos-mcp;
      };
    };
}
