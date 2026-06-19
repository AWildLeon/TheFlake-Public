let
  users = import (builtins.getEnv "GIT_ROOT" + "/secrets/age_pubkeys.nix");
  host_keys = [ "ssh-ed25519 ..." ];
  combined_keys = users ++ host_keys;
in
{
  "./secrets/example.age".publicKeys = combined_keys;
}
