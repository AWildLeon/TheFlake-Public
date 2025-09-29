{ lib, ... }: {
  imports = [ ./base.nix ];

  # Enable bootserver service
  lh.services.bootserver = {
    enable = lib.mkDefault true;
    proxyDhcp.enable = true;

    # Basic configuration
    domain = lib.mkDefault "bootserver.internal";
  };
}
