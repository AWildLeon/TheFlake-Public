{ config
, pkgs
, lib
, ...
}:

let
  width = 70;
  font = "slant"; # try: "small", "mini", "banner", "lean"
  rule = lib.concatStrings (lib.replicate width "=");

  # Generate clean ASCII (escape \ -> \\ for literal display; trim trailing spaces)
  hostnameAscii = pkgs.runCommand "hostname-ascii" { } ''
    ${pkgs.figlet}/bin/figlet -f ${font} -w ${toString width} -k -- "${config.networking.hostName}" \
      | sed -e 's/[[:space:]]*$//' -e 's/\\/\\\\/g' > $out
  '';

  # ANSI wrappers for TTY stability
  esc = "\\x1b";
  prelude = "${esc}[?7l${esc}(B${esc}[0m${esc}[3g"; # no-wrap, sane charset, reset, clear tabs
  postlude = "${esc}[0m${esc}[?7h"; # reset + re-enable wrap

  # Build /etc/issue with escapes so agetty won’t mangle it
  issueAnsi = pkgs.runCommand "issue-ansi" { } ''
    {
      printf '${prelude}'
      cat ${hostnameAscii}

      echo
      echo '${rule}'
      echo
      echo 'Unauthorized access to ${config.networking.hostName} is prohibited.'
      echo
      echo 'System Information:'
      echo '├─ NixOS version: ${config.system.stateVersion}'
      echo '└─ Kernel: ${config.boot.kernelPackages.kernel.version}'
      echo
      echo '${rule}'

      printf '${postlude}\n'
    } > $out
  '';

  # Plaintext MOTD (SSH), no escapes needed
  issueText = ''
    ${builtins.readFile hostnameAscii}

    ${rule}

    Unauthorized access to ${config.networking.hostName} is prohibited.

    System Information:
    ├─ NixOS version: ${config.system.stateVersion}
    └─ Kernel: ${config.boot.kernelPackages.kernel.version}

    ${rule}
  '';

in
{
  # Predictable glyph widths on the console
  # console.font = "Lat2-Terminus16";

  environment = {
    systemPackages = with pkgs; [ figlet ];

    # SSH + local MOTD (plaintext)
    etc."motd".text = issueText;

    # TTY login screen (with VT escapes)
    etc."issue".source = issueAnsi;
  };

  boot.kernelParams = [ "vt.default_utf8=1" ];

  console = {
    font = "ter-v18n"; # good Unicode coverage incl. box-drawing
    packages = [ pkgs.terminus_font ];
  };
  # (Optional) also expose as issue.net and point agetty at it if you prefer
  # environment.etc."issue.net".source = issueAnsi;
  # systemd.services."getty@tty1".serviceConfig.ExecStart = lib.mkForce
  #   ''${pkgs.util-linux}/bin/agetty --noclear --issue-file /etc/issue.net %I 115200 linux'';
}
