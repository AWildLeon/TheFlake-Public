{
  inputs,
  ...
}:
{
  imports = [
    inputs.self.diskoConfigurations.default-v1-vda
    inputs.self.nixosModules.profile_qemu-guest-x86_64-linux
    ./network.nix

  ];
  lh = {
    roleSystem.systemType = "server";
    system = {
      impermanence.enable = true;
      serialtty = {
        enable = true;
        autoLogin = true;
      };
    };
  };
}
