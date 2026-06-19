{
  lh,
  pkgs,
  ...
}:
let
  sshLocalNetwork = pkgs.writeText "ssh-localnetwork" ''
    Host 10.* 192.168.* 172.[16-31].*
        UserKnownHostsFile /dev/null
        StrictHostKeyChecking no
  '';
in
{

  systemd.user.tmpfiles.rules = [
    "d /home/leon/.ssh/cm 0700 leon leon -"
    "d /home/leon/.ssh/keys 0700 leon leon -"
  ];

  # SSH Config
  programs.ssh =
    let
      proxyCommand = "${pkgs.step-cli}/bin/step ssh proxycommand --provisioner authentik  %r %h %p";
    in
    {
      enable = true;
      enableDefaultConfig = false;

      matchBlocks =
        lh.lib.home.mkInventorySshHosts {
          inherit proxyCommand;
        }
        // {
          "git.example.com" = {
            port = 2222;
            user = "gitea";
            identityFile = "~/.ssh/keys/git_example_com";
          };

          "git.dn42.dev" = {
            port = 22;
            user = "git";
            identityFile = "~/.ssh/keys/dn42";
          };

          "*" = {
            user = "root";
          };
        };

      extraConfig = ''
        IgnoreUnknown GSSAPIKeyAlgorithms
        PubkeyAcceptedKeyTypes ^ssh-ed25519,sk-ssh-ed25519@openssh.com
        HostKeyAlgorithms ^ssh-ed25519
        ForwardAgent yes
        AddKeysToAgent yes

        Compression no
        ControlMaster auto
        ControlPersist 30m
        ControlPath ~/.ssh/cm/%i-%C.sshsock
        ServerAliveInterval 60
        ServerAliveCountMax 3
        SetEnv TERM=xterm-256color
      '';

      includes = [
        "${sshLocalNetwork}"
        "vscode-hosts.conf"
        "~/.ssh/config.d/*"
      ];
    };
}
