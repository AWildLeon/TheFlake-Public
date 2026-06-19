{ inputs, ... }:
{

  nix = {
    # Pin <nixpkgs> and the `nixpkgs` flake registry entry to this flake's
    # nixpkgs input. Without this there is no nixpkgs channel, so `<nixpkgs>`
    # fails to resolve — which crashes nixd's eval worker on startup (it
    # evaluates `import <nixpkgs>` before LSP config arrives, leaving the value
    # in an error state that aborts on the first attrpathInfo request).
    nixPath = [ "nixpkgs=flake:nixpkgs" ];
    registry.nixpkgs.flake = inputs.nixpkgs;

    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;

      extra-substituters = [
        "https://awildleon-nixlib.cachix.org"
        "https://nix-community.cachix.org"
      ];
      extra-trusted-public-keys = [
        "awildleon-nixlib.cachix.org-1:jDsApfkbRWepIRrxDVVFUJHQLuAgliX0WTicUnTs9rI="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];

      # Larger download buffer to avoid "download buffer is full" warnings and
      # throttling when substituting many/large paths (default is 64 MiB).
      download-buffer-size = 268435456; # 256 MiB

      allowed-users = [
        "root"
      ];
    };

    optimise = {
      dates = [ "01:00" ];
      automatic = true;
    };

    gc = {
      automatic = true;
      persistent = true;
      dates = "daily";
      options = "--delete-older-than 7d";
    };

  };
  nixpkgs.config.allowUnfree = true;
}
