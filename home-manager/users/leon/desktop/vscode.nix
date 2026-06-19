{
  inputs,
  pkgsUnstable,
  pkgs,
  lib,
  ...
}:
{

  # Disable stylix for VS Code specifically
  stylix.targets.vscode.enable = lib.mkForce false;

  programs.vscode = {
    enable = true;
    mutableExtensionsDir = true;
    package = pkgsUnstable.vscode;
    profiles.default = {
      extensions =
        inputs.nix4vscode.lib.${pkgs.stdenv.hostPlatform.system}.forVscodeVersion
          pkgsUnstable.vscode.version
          [
            # AI
            #"github.copilot-chat"
            #"github.copilot"

            # Remote - SSH
            "ms-vscode-remote.remote-ssh"
            "ms-vscode-remote.remote-ssh-edit"
            "ms-vscode-remote.remote-containers"
            "ms-vscode.remote-explorer"

            # GitHub / Git
            "github.remotehub"
            "ms-vscode.remote-repositories"
            "github.vscode-github-actions"

            # C#
            "ms-dotnettools.csdevkit"
            "ms-dotnettools.csharp"

            # Python
            "ms-python.python"
            "ms-python.debugpy"
            "ms-python.vscode-pylance"
            "ms-python.vscode-python-envs"

            # Docker
            "ms-azuretools.vscode-docker"

            # MISC
            "yzhang.markdown-all-in-one"
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
          ];
      enableUpdateCheck = false;
      enableExtensionUpdateCheck = false;
      userSettings = {
        "telemetry.telemetryLevel" = "off";
        "http.systemCertificatesNode" = true;
        "geminicodeassist.project" = "agile-diagram-h4p0d";
        "git.enableSmartCommit" = true;
        "ansible.lightspeed.enabled" = false;
        "security.workspace.trust.enabled" = false;
        "remote.SSH.experimental.enhancedSessionLogs" = false;
        "telemetry.editStats.enabled" = false;
        "update.showReleaseNotes" = false;
        "remote.SSH.enableDynamicForwarding" = false;
        "editor.formatOnSave" = true;
        "remote.SSH.externalSSH_ASKPASS" = true;
        "remote.SSH.experimental.chat" = false;
        "remote.SSH.showLoginTerminal" = true;
        "github.copilot.enable" = {
          "*" = false;
          "plaintext" = false;
          "markdown" = false;
          "scminput" = false;
          "dockercompose" = false;
          "csharp" = true;
          "yaml" = true;
          "nix" = true;
          "json" = true;
          "python" = true;
          "shellscript" = true;
          "terraform" = true;
          "packer" = true;
          "dockerfile" = true;
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
        "editor.fontFamily" = "'DejaVuSansM Nerd Font Mono', 'monospace', monospace";
        "vsicons.dontShowNewVersionMessage" = true;
        "github.copilot.nextEditSuggestions.enabled" = true;
        "[markdown]" = {
          "editor.defaultFormatter" = "yzhang.markdown-all-in-one";
        };
        "gitlens.ai.model" = "vscode";
        "[json]" = {
          "editor.defaultFormatter" = "esbenp.prettier-vscode";
        };
        "terminal.integrated.stickyScroll.enabled" = false;
      };
    };
  };
}
