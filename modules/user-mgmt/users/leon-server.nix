{ lib, ... }:
{
  users.users."leon" = {
    group = "users";
    extraGroups = [
      "wheel"
      "docker"
    ];
    isNormalUser = true;
  };

  security.sudo = {
    execWheelOnly = true;
    enable = lib.mkForce true;
    extraRules = [
      {
        users = [ "leon" ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
