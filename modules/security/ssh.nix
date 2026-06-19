{ lib, config, ... }:

with lib;

let
  cfg = config.lh.security.ssh;
in
{
  options.lh.security.ssh = {
    enable = mkEnableOption "Enable secure SSH configuration with CA-based authentication";

    permitRootLogin = mkOption {
      type = types.bool;
      default = true;
      description = "Allow root login via SSH";
    };

    allowAgentForwarding = mkOption {
      type = types.bool;
      default = true;
      description = "Allow SSH agent forwarding";
    };

    allowTcpForwarding = mkOption {
      type = types.bool;
      default = true;
      description = "Allow TCP forwarding";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Additional SSH daemon configuration";
    };
  };

  config = mkIf cfg.enable {

    users.users = {
      root.openssh.authorizedPrincipals = [
        "mail@example.com"
        "nixarchitect@example.com"
      ];
    };

    services.openssh = {
      enable = true;
      extraConfig = ''
        TrustedUserCAKeys ${./ssh_ca.pub}
        AuthenticationMethods publickey
        AllowAgentForwarding ${if cfg.allowAgentForwarding then "yes" else "no"}
        AllowTcpForwarding ${if cfg.allowTcpForwarding then "yes" else "no"}
        ${cfg.extraConfig}
      '';

      sftpServerExecutable = "internal-sftp";
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = if cfg.permitRootLogin then "yes" else "no";
      };
    };
  };
}
