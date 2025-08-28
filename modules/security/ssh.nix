_:
let
  sshca = builtins.fetchurl {
    url = "https://sshca.onlh.de/combined.pub";
    sha256 = "1s7x1276h9m0vvwlyq3xsznag1bk25qpdxn6giyzv0li8cwlyayv";
  };

in
{
  services.openssh = {
    enable = true;
    extraConfig = ''
      TrustedUserCAKeys ${sshca}
      AuthenticationMethods publickey
      AllowAgentForwarding yes
      AllowTcpForwarding yes
    '';

    sftpServerExecutable = "internal-sftp";
    # require public key authentication for better security
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "yes";
    };
    # startWhenNeeded = true;

  };

}
