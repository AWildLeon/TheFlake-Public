{ config, lib, ... }:
{
  options.lh.router.radvd = {
    enable = lib.mkEnableOption "Enable radvd for IPv6 router advertisements";
    interfaces = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Name of the interface";
            };
            prefixes = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "List of IPv6 prefixes to advertise on this interface";
            };
          };
        }
      );
      example = [
        {
          name = "eth1";
          prefixes = [ "fdca::/64" ];
        }
      ];
      default = [ ];
      description = "List of interfaces to enable radvd on";
    };
    dns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "2620:fe::fe"
        "2620:fe::9"
      ];
      description = "List of RDNSS servers to advertise";
    };
  };

  config = lib.mkIf config.lh.router.radvd.enable {
    services.radvd = {
      enable = true;
      config = lib.concatStringsSep "\n" (
        map (interface: ''
          interface ${interface.name}
          {
              AdvSendAdvert on;
              MaxRtrAdvInterval 30;
              AdvDefaultLifetime 1800;
              AdvManagedFlag off;
              AdvOtherConfigFlag off;

          ${lib.concatStringsSep "\n" (
            map (prefix: ''
              prefix ${prefix}
              {
                  AdvOnLink on;
                  AdvAutonomous on;
                  AdvValidLifetime 86400;
                  AdvPreferredLifetime 14400;
              };
            '') interface.prefixes
          )}

          ${lib.optionalString (config.lh.router.radvd.dns != [ ]) (
            lib.concatStringsSep "\n" (
              map (dnsServer: ''
                RDNSS ${dnsServer}
                {
                    AdvRDNSSLifetime 600;
                };
              '') config.lh.router.radvd.dns
            )
          )}
          };
        '') config.lh.router.radvd.interfaces
      );
    };
  };
}
