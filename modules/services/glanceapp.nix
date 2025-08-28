{lib, config, options,...}: {

  options.lh.services.glance = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable Glance (https://github.com/glanceapp/glance).
      '';
    };
  };

  config = lib.mkIf config.lh.services.glance.enable {
    services.glance = {
      enable = true;
      openFirewall = false;
    };

    #systemd.services.glance
  };
  
}