{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      pkgsUnstable,
      self',
      ...
    }:
    {
      devShells.default =
        let
          arch = pkgs.stdenv.hostPlatform.system;
        in
        pkgs.mkShell {
          packages = with pkgs; [
            ansible
            ansible-lint
            openssh
            terraform
            packer
            python3
            nixd
            nodejs
            python3Packages.proxmoxer
            pkgsUnstable.mcp-nixos
            ripgrep
            socat
            bubblewrap
            jq
            yq-go
            tree
            fd
            file
            diffutils
            patch
            rsync
            curl
            inputs.agenix.packages.${arch}.default
            inputs.colmena.packages.${arch}.colmena
            self'.packages.lhflake

            # AI Tools
            self'.packages.pi-nixos-mcp
            inputs.self.packages.${arch}.bubblewrapped.llm.codex
            inputs.self.packages.${arch}.bubblewrapped.llm.pi
            inputs.self.packages.${arch}.bubblewrapped.llm.gemini
            inputs.self.packages.${arch}.bubblewrapped.llm.claude
          ];
        };
    };
}
