{ pkgs, lib, osConfig, pkgsUnstable, ... }:

let
  hostname = osConfig.networking.hostName or "";
  ssh-localnetwork = pkgs.writeText "ssh-localnetwork" ''
    Host 10.* 192.168.* 172.[16-31].*
        UserKnownHostsFile /dev/null
        StrictHostKeyChecking no
  '';

in
{
  # Disable stylix for VS Code specifically
  stylix.targets.vscode.enable = lib.mkForce false;

  xdg.autostart = {
    enable = true;
    entries = lib.optionals (hostname == "lh-pc")
      [ (pkgs.spotify + "/share/applications/spotify.desktop") ];
  };

  programs.chromium = {
    enable = true;
    package = pkgs.brave;
    nativeMessagingHosts = [ pkgs.kdePackages.plasma-browser-integration ];
    extensions = [
      { id = "nngceckbapebfimnlniiiahkandclblb"; } # Bitwarden
      { id = "iadbdpnoknmbdeolbapdackdcogdmjpe"; } # Addy
      { id = "oldceeleldhonbafppcapldpdifcinji"; } # Language Tool
      { id = "icpgjfneehieebagbmdbhnlpiopdcmna"; } # New Tab Redirect
      { id = "mnjggcdmjocbbbhaepdhchncahnbgone"; } # Sponsor Block
      { id = "nddaaiojgkoldnhnmkoldmkeocbooken"; } # Yourls
      { id = "ndpmhjnlfkgfalaieeneneenijondgag"; } # YT Anti Translate
    ];
  };

  programs = {
    git = {
      enable = true;
      userName = "Leon Hubrich";
      userEmail = "git@leon-hubrich.de";
      extraConfig = { pull.rebase = true; };
    };

    vscode = {
      enable = true;
      mutableExtensionsDir = true;
      package = pkgsUnstable.vscode;
      profiles.default = {
        extensions = pkgs.nix4vscode.forVscode [
          # AI
          "github.copilot-chat"
          "github.copilot"

          # Remote - SSH
          "ms-vscode-remote.remote-ssh"
          "ms-vscode-remote.remote-ssh-edit"
          "ms-vscode-remote.remote-containers"
          "ms-vscode.remote-explorer"

          # GitHub / Git
          "github.remotehub"
          "ms-vscode.remote-repositories"
          "github.vscode-github-actions"
          "eamodio.gitlens"

          # C#
          "ms-dotnettools.csdevkit"
          "ms-dotnettools.csharp"
          "ms-dotnettools.vscodeintellicode-csharp"

          # Python
          "ms-python.python"
          "ms-python.debugpy"
          "ms-python.vscode-pylance"
          "ms-python.vscode-python-envs"

          # Docker
          "ms-azuretools.vscode-docker"

          # MISC
          "yzhang.markdown-all-in-one"
          "yzane.markdown-pdf"
          "visualstudioexptteam.vscodeintellicode"
          "redhat.vscode-yaml"
          "mechatroner.rainbow-csv"

          # Terraform / Packer
          "hashicorp.terraform"
          "4ops.packer"

          # Nix
          "jnoortheen.nix-ide"
          "mkhl.direnv"

          # Theme
          "vscode-icons-team.vscode-icons"
          "jdinhlife.gruvbox"

          # Java
          "vscjava.vscode-java-pack"
          "redhat.java"
          "vscjava.vscode-java-debug"
          "vscjava.vscode-java-test"
          "vscjava.vscode-maven"
          "vscjava.vscode-gradle"
          "vscjava.vscode-java-dependency"
        ];
        enableUpdateCheck = false;
        enableExtensionUpdateCheck = false;
        userSettings = {
          "telemetry.telemetryLevel" = "off";
          "git.enableSmartCommit" = true;
          "ansible.lightspeed.enabled" = false;
          "security.workspace.trust.enabled" = false;
          "remote.SSH.experimental.enhancedSessionLogs" = false;
          "telemetry.editStats.enabled" = false;
          "update.showReleaseNotes" = false;
          "github.copilot.enable" = {
            "*" = false;
            "plaintext" = false;
            "markdown" = false;
            "scminput" = false;
            "dockercompose" = false;
            "yaml" = true;
            "nix" = true;
            "json" = true;
            "python" = true;
            "shellscript" = true;
          };
          "docker.extension.enableComposeLanguageServer" = true;
          "workbench.sideBar.location" = "right";
          "chat.agent.maxRequests" = 250;
          "telemetry.feedback.enabled" = false;
          "nix.enableLanguageServer" = true;
          "git.confirmSync" = false;
          "nix.serverSettings"."nil"."formatting"."command" = [ "nixfmt" ];
          "files.autoSave" = "onFocusChange";
          "workbench.iconTheme" = "vscode-icons";
          "workbench.colorTheme" = "Gruvbox Dark Hard";
          "vsicons.dontShowNewVersionMessage" = true;
          "github.copilot.nextEditSuggestions.enabled" = true;
          "[markdown]" = {
            "editor.defaultFormatter" = "yzhang.markdown-all-in-one";
          };
        };
      };
    };

    # SSH Config
    ssh = {
      enable = true;
      serverAliveInterval = 60;
      serverAliveCountMax = 3;

      matchBlocks = {
        "ita1-fra" = {
          hostname = "ita1-fra.bgp.pop.as213579.de";
          user = "leon";
        };
        "eth1-fra" = {
          hostname = "eth1-fra.bgp.pop.as213579.de";
          user = "leon";
        };
        "*.bgp.pop.as213579.de" = { user = "leon"; };

        "nixarchitect" = {
          hostname = "10.0.5.254";
          user = "leon";
        };

        "openems-dev" = {
          hostname = "77.90.48.18";
          user = "leon";
        };

        "cdn" = { hostname = "77.90.48.30"; };

        "bastion" = { hostname = "77.90.48.7"; };

        "netcup-docker1" = { hostname = "152.53.131.121"; };

        "realtox1" = { hostname = "77.90.42.72"; };

        "nas" = { hostname = "10.0.0.2"; };

        "lh-pc" = { hostname = "2a14:47c0:e002::4"; };

        "lh-laptop" = { hostname = "10.0.5.216"; };

        "ns1.onlh.de" = { hostname = "77.90.48.5"; };

        "tcn-netcup2" = { hostname = "152.53.185.83"; };

        "papa-docker" = { hostname = "192.168.176.201"; };

        "VPN-Router" = { hostname = "10.0.254.8"; };

        "lh-tvpc" = { hostname = "10.0.3.3"; };

        "newFortress" = { hostname = "newfortress.nodes.lhnetworks.de"; };
      };

      extraConfig = ''
        user root
        IdentityFile ~/.ssh/keys/blue
        IdentityFile ~/.ssh/keys/white
        PubkeyAcceptedKeyTypes ^ssh-ed25519,sk-ssh-ed25519@openssh.com
        HostKeyAlgorithms ^ssh-ed25519
      '';

      includes =
        [ "${ssh-localnetwork}" "vscode-hosts.conf" "~/.ssh/config.d/*" ];
    };
  };

  services.kdeconnect = {
    enable = true;
    package = pkgs.kdePackages.kdeconnect-kde;
    indicator = true;
  };

  home.packages = with pkgs; [ git-filter-repo pipx ];

  home.stateVersion = "24.05";
}
