let
  small = import ./small-vm.nix;
in
small
// {
  cores = 4;
  memory = 4096;
}
