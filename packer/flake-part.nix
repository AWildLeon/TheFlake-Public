{
  inputs,
  self,
  ...
}:
{
  perSystem =
    {
      system,
      pkgs,
      lib,
      ...
    }:
    let
      python = pkgs.python3.withPackages (
        python-pkgs: with python-pkgs; [
          # select Python packages here
          proxmoxer
          requests
        ]
      );
      runtimeDeps = with pkgs; [
        packer
        openssh
        bash
        coreutils
        nixos-anywhere

        python
        ansible
      ];

      mkPackerPackage =
        { name, path }:
        pkgs.writeText "${name}.json" (
          builtins.toJSON (
            import path {
              inherit pkgs inputs self;
              lib = packerLib { inherit pkgs inputs self; };
            }
          )
        );

      mkPackerRunner =
        { name, packerFile }:
        {
          type = "app";
          program = toString (
            pkgs.writers.writeBash name ''
              export PATH=${lib.makeBinPath runtimeDeps}
              packer build "$@" ${packerFile} 
            ''
          );
        };

      packerLib = args: import ./lib args;
    in
    {
      packages.packer_proxmox_nixos = mkPackerPackage {
        name = "packer-proxmox-nixos";
        path = ./proxmox/nixos;
      };

      packages.packer_proxmox_debian = mkPackerPackage {
        name = "packer-proxmox-debian";
        path = ./proxmox/debian;
      };

      devShells.packer = pkgs.mkShell {
        buildInputs = runtimeDeps;
      };

      apps.run-packer-proxmox-nixos = mkPackerRunner {
        name = "run-packer-proxmox-nixos";
        packerFile = self.packages.${pkgs.stdenv.hostPlatform.system}.packer_proxmox_nixos;
      };

      apps.run-packer-proxmox-debian = mkPackerRunner {
        name = "run-packer-proxmox-debian";
        packerFile = self.packages.${pkgs.stdenv.hostPlatform.system}.packer_proxmox_debian;
      };
    };
}
