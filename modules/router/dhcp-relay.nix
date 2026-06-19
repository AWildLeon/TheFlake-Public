{
  options,
  config,
  lib,
  ...
}:
{

  options.lh.router.dhcpRelay = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable DHCP Relay functionality on this router.";
    };
    interfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of interfaces to enable DHCP Relay on.";
    };

    relay = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "The DHCP server to which requests should be relayed.";
    };

    upstreamInterface = lib.mkOption {
      type = lib.types.str;
      default = "backbone";
      description = "The interface on which the DHCP server is reachable.";
    };
    ignoreInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of interfaces on which DHCP Relay should not listen.";
    };
  };

  config = lib.mkIf config.lh.router.dhcpRelay.enable {
    services.dnsmasq = {
      enable = true;
      resolveLocalQueries = false;
      settings = {

        interface = [
          config.lh.router.dhcpRelay.upstreamInterface
        ]
        ++ config.lh.router.dhcpRelay.interfaces;
        bind-interfaces = true;
        port = 0;

        # Relays (local-addr muss *auf dem Interface existieren*)
        dhcp-relay = config.lh.router.dhcpRelay.relay;

        no-dhcp-interface = [
          config.lh.router.dhcpRelay.upstreamInterface
        ]
        ++ config.lh.router.dhcpRelay.ignoreInterfaces;
      };
    };
  };
}
