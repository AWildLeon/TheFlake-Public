{ lib, config, ... }:

with lib;

let
  cfg = config.lh.security.ssh;
in
{
  options.lh.security.ssh = {
    enable = mkEnableOption "Enable secure SSH configuration with CA-based authentication";

    sshCAUrl = mkOption {
      type = types.str;
      default = "https://sshca.onlh.de/combined.pub";
      description = "URL to fetch SSH Certificate Authority public keys";
    };

    sshCAHash = mkOption {
      type = types.str;
      default = "1s7x1276h9m0vvwlyq3xsznag1bk25qpdxn6giyzv0li8cwlyayv";
      description = "SHA256 hash of the SSH CA file";
    };

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
    services.openssh = {
      enable = true;
      extraConfig = ''
        TrustedUserCAKeys ${builtins.fetchurl {
          url = cfg.sshCAUrl;
          sha256 = cfg.sshCAHash;
        }}
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
