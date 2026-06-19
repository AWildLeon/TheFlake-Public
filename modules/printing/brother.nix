{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.lh.printing.brother;
in
{
  options.lh.printing.brother = {
    enable = lib.mkEnableOption "Enable Brother printer configuration";
    devices = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption { type = lib.types.str; };
            model = lib.mkOption { type = lib.types.str; };
            ip = lib.mkOption { type = lib.types.str; };
          };
        }
      );
      default = [ ];
      description = "Brother printer devices to configure.";
    };
  };

  config = lib.mkIf cfg.enable {
    lh.printing.default.enable = lib.mkForce true;

    hardware.sane = {
      extraBackends = with pkgs; [
        brscan4
        sane-airscan
      ];
      brscan4 = {
        enable = true;
        netDevices = lib.listToAttrs (
          lib.imap0 (_i: device: {
            inherit (device) name;
            value = {
              inherit (device) model ip;
            };
          }) cfg.devices
        );
      };
    };

    services.printing = {
      enable = true;
      drivers = with pkgs; [ brlaser ];
    };

    hardware.printers.ensurePrinters =
      lib.mapAttrsToList
        (name: device: {
          name = lib.replaceStrings [ " " ] [ "_" ] name;
          deviceUri = "ipp://" + device.ip + "/ipp/port1";
          model = "drv:///brlaser.drv/brl2710d.ppd";
          ppdOptions = {
            PageSize = "A4";
          };
        })
        (
          lib.listToAttrs (
            lib.imap0 (_i: device: {
              inherit (device) name;
              value = {
                inherit (device) model ip;
              };
            }) cfg.devices
          )
        );

  };
}
