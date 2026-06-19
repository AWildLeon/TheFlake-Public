{
  inputs,
  system,
  pkgs,
  pkgsUnstable,
  mkNixPak,
}:
let
  llm = inputs.llm-agents.packages.${system};

  llmSandboxPath =
    with pkgs;
    pkgs.lib.makeBinPath [
      bashInteractive
      coreutils
      curl
      diffutils
      fd
      file
      findutils
      gawk
      git
      gnugrep
      gnused
      jq
      nix
      nodejs
      openssh
      patch
      python3
      ripgrep
      rsync
      socat
      tree
      which
      yq-go
      llm.claude-code
      llm.codex
      llm.gemini-cli
      inputs.agenix.packages.${system}.default
      inputs.colmena.packages.${system}.colmena
      pkgsUnstable.mcp-nixos
      inputs.self.packages.${system}.lhflake
      inputs.self.packages.${system}.pi-nixos-mcp
    ];

  commonConfigPaths = [
    ".gitconfig"
    ".config/git"
  ];

  homePath = sloth: path: sloth.concat' sloth.homeDir "/${path}";
in
{
  package,
  configPaths ? [ ],
}:
let
  appName = package.meta.mainProgram or (pkgs.lib.getName package);
in
(mkNixPak {
  config =
    { sloth, ... }:
    {
      app.package = package;
      app.binPath = "bin/${appName}";

      # These are CLI tools; D-Bus proxying only adds noise and deps.
      dbus.enable = false;

      bubblewrap = {
        clearEnv = true;
        dieWithParent = true;
        network = true;

        env = {
          HOME = sloth.homeDir;
          TMPDIR = "/tmp";
          XDG_CACHE_HOME = sloth.concat' sloth.homeDir "/.cache";
          XDG_CONFIG_HOME = sloth.concat' sloth.homeDir "/.config";
          XDG_DATA_HOME = sloth.concat' sloth.homeDir "/.local/share";
          USER = sloth.env "USER";
          TERM = sloth.envOr "TERM" "xterm-256color";
          SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
          NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
          NIX_REMOTE = "daemon";
          PATH = llmSandboxPath;
          PWD = sloth.env "PWD";
        };

        tmpfs = [
          "/tmp"
          "/run"
        ];

        bind.ro = [
          "/etc"
        ];

        bind.rw = [
          "/nix/var/nix/daemon-socket/socket"

          # Always expose the directory the agent was launched from and keep
          # the same path inside the sandbox so inherited cwd/PWD continue to
          # work.
          (sloth.env "PWD")
        ]
        ++ map (path: homePath sloth path) (commonConfigPaths ++ configPaths);
      };
    };
}).config.script
