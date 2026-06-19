let
  small = import ./small-vm.nix;
in
small
// {
  cores = 8;
  memory = 8192;
}
