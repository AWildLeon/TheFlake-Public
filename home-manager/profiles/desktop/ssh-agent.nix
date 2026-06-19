{ config, ... }:
{
  services.ssh-agent = {
    enable = true;
    defaultMaximumIdentityLifetime = 60 * 60 * 2; # 2h
  };

  xdg.configFile = {
    "environment.d/10-ssh-agent.conf".text = ''
      SSH_AUTH_SOCK=''${XDG_RUNTIME_DIR}/ssh-agent
    '';

    "systemd/user/ssh-agent.socket".source = config.lib.file.mkOutOfStoreSymlink "/dev/null";
  };
}
