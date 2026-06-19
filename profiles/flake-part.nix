_: {
  flake.nixosModules = {
    profile_defaults = import ./hosts/defaults;
    profile_qemu-guest-x86_64-linux = import ./hosts/qemu-guest-x86_64-linux;
  };
}
