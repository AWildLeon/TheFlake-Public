{ pkgsUnstable
, lib
, config
, ...
}:

let
  cfg = config.lh.services.nameserver;
in

{
  imports = [ ];

  options.lh.services.nameserver = {
    fqdn = lib.mkOption {
      type = lib.types.str;
      default = config.networking.fqdn or "${config.networking.hostName}.local";
      description = "The FQDN for the nameserver web interface";
      example = "dns.example.com";
    };
    enable = lib.mkEnableOption "Technitium DNS Server";
  };

  config = lib.mkIf cfg.enable {

    # Enable the nginx service module
    lh.services.nginx.enable = true;

    services.technitium-dns-server = {
      enable = true;
      openFirewall = true;
      package = pkgsUnstable.technitium-dns-server;
    };

    # Create user and group for the service
    users.users.technitium-dns-server = {
      group = "technitium-dns-server";
      isSystemUser = true;
      home = "/var/lib/nameserver";
      createHome = false; # StateDirectory will handle this
    };

    users.groups.technitium-dns-server = { };

    # Nginx reverse proxy for Technitium DNS Server
    services.nginx.virtualHosts = {
      "${cfg.fqdn}" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:5380";
          proxyWebsockets = true;
          extraConfig = ''
            # proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            # proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            # proxy_set_header X-Forwarded-Proto $scheme;

            # Handle large uploads for DNS zone files
            client_max_body_size 10M;

            # Increase timeouts for DNS operations
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
          '';
        };
      };
    };

    # systemd-Overrides für die Unit
    systemd.services.technitium-dns-server.serviceConfig = {
      # Use /var/lib/nameserver instead of the default technitium-dns-server
      StateDirectory = lib.mkForce "nameserver";
      WorkingDirectory = lib.mkForce "/var/lib/nameserver";
      ExecStart = lib.mkForce "${pkgsUnstable.technitium-dns-server}/bin/technitium-dns-server /var/lib/nameserver";
      # Disable DynamicUser to avoid conflicts with existing directory
      DynamicUser = lib.mkForce false;
      # Set a specific user instead
      User = "technitium-dns-server";
      Group = "technitium-dns-server";

      BindPaths = lib.mkForce [ ];
    };

    # Persistenz via impermanence
    environment =
      lib.optionalAttrs
        (builtins.hasAttr "environment" config && builtins.hasAttr "persistence" config.environment)
        {
          persistence."/persistent" = {
            directories = [ "/var/lib/nameserver" ];
          };
        };
  };
}
