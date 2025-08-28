_: {

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;

      allowed-users = [
        "root"
        "leon"
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
}
