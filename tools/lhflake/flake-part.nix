{ inputs, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      subcommands = [
        "technitium-zone-sync"
        "proxmox-sync"
        "wg-rekey"
        "rekey-recursive"
        "discover-ssh-keys"
        "dependency-graph"
        "packet"
        "help"
      ];

      subcommandList = lib.concatStringsSep " " subcommands;

      script = pkgs.writeShellApplication {
        name = "lhflake";
        runtimeInputs = [
          pkgs.nix
          pkgs.git
          pkgs.bash
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnused
          pkgs.openssh
          pkgs.python3
          pkgs.mermaid-cli
          pkgs.wireguard-tools
          inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
        ];
        text = ''
          subcommand="''${1:-}"
          shift || true

          if git rev-parse --show-toplevel > /dev/null 2>&1; then
            FLAKE_ROOT="$(git rev-parse --show-toplevel)"
          else
            echo "Error: not in a git repository" >&2
            exit 1
          fi

          usage() {
            echo "Usage: lhflake <subcommand> [args]"
            echo ""
            echo "Subcommands:"
            echo "  technitium-zone-sync   Sync DNS zones to Technitium"
            echo "  proxmox-sync           Sync Proxmox nodes"
            echo "  wg-rekey               Regenerate WireGuard keypairs"
            echo "  rekey-recursive        Recursively rekey host-local agenix secrets"
            echo "  discover-ssh-keys      Discover host ed25519 SSH keys into meta.nix"
            echo "  dependency-graph       Visualize deployment dependencies"
            echo "  packet                 Simulate/debug lh.firewall packet verdicts"
          }

          case "$subcommand" in
            technitium-zone-sync|proxmox-sync|packet)
              exec nix run "''${FLAKE_ROOT}#''${subcommand}" -- "$@"
              ;;
            wg-rekey)
              exec ${pkgs.bash}/bin/bash "''${FLAKE_ROOT}/tools/wireguard/wg-rekey" "$@"
              ;;
            rekey-recursive)
              exec ${pkgs.bash}/bin/bash "''${FLAKE_ROOT}/tools/secrets/rekey-recursive" "$@"
              ;;
            discover-ssh-keys)
              exec ${pkgs.python3}/bin/python "''${FLAKE_ROOT}/tools/inventory/discover-ssh-ed25519-keys.py" "$@"
              ;;
            dependency-graph)
              exec ${pkgs.python3}/bin/python "''${FLAKE_ROOT}/tools/inventory/dependency-graph.py" --flake-root "''${FLAKE_ROOT}" "$@"
              ;;
            help|--help|-h|"")
              usage
              ;;
            *)
              echo "Unknown subcommand: $subcommand" >&2
              usage >&2
              exit 1
              ;;
          esac
        '';
      };

      bashCompletion = pkgs.writeText "lhflake-bash-completion" ''
        _lhflake() {
          local cur="''${COMP_WORDS[COMP_CWORD]}"
          local prev="''${COMP_WORDS[COMP_CWORD-1]}"

          if [[ $COMP_CWORD -eq 1 ]]; then
            COMPREPLY=($(compgen -W "${subcommandList}" -- "$cur"))
            return
          fi

          case "$prev" in
            wg-rekey)
              COMPREPLY=($(compgen -W "--a-dir --a-privkey --a-psk --b-dir --b-privkey --b-psk --help" -- "$cur"))
              ;;
            rekey-recursive)
              COMPREPLY=($(compgen -W "--dry-run --continue --verbose --agenix-bin --help" -- "$cur"))
              ;;
            discover-ssh-keys)
              COMPREPLY=($(compgen -W "--dry-run --force --continue --timeout --verbose --help" -- "$cur"))
              ;;
            dependency-graph)
              COMPREPLY=($(compgen -W "--format --output --host --reverse --no-validate --help" -- "$cur"))
              ;;
            packet)
              COMPREPLY=($(compgen -W "--path --from --to --src --dst --proto --sport --dport --ct-state --ct-mark --mark --tcp-flags --json --examples --list-zones --list-interfaces --dump-model --help" -- "$cur"))
              ;;
          esac
        }
        complete -F _lhflake lhflake
      '';

      zshCompletion = pkgs.writeText "_lhflake" ''
        #compdef lhflake

        _lhflake() {
          local state

          _arguments \
            '1:subcommand:->subcommand' \
            '*::args:->args'

          case $state in
            subcommand)
              local -a cmds
              cmds=(
                'technitium-zone-sync:Sync DNS zones to Technitium'
                'proxmox-sync:Sync Proxmox nodes'
                'wg-rekey:Regenerate WireGuard keypairs'
                'rekey-recursive:Recursively rekey host-local agenix secrets'
                'discover-ssh-keys:Discover host ed25519 SSH keys into meta.nix'
                'dependency-graph:Visualize deployment dependencies'
                'packet:Simulate/debug lh.firewall packet verdicts'
                'help:Show usage'
              )
              _describe 'subcommand' cmds
              ;;
            args)
              case ''${words[1]} in
                wg-rekey)
                  _arguments \
                    '--a-dir[Path to host A directory]:dir:_directories' \
                    '--a-privkey[Host A private key filename]:file' \
                    '--a-psk[Host A PSK filename]:file' \
                    '--b-dir[Path to host B directory]:dir:_directories' \
                    '--b-privkey[Host B private key filename]:file' \
                    '--b-psk[Host B PSK filename]:file'
                  ;;
                rekey-recursive)
                  _arguments \
                    '(-n --dry-run)'{-n,--dry-run}'[Only print directories that would be rekeyed]' \
                    '(-c --continue)'{-c,--continue}'[Continue after failures]' \
                    '(-v --verbose)'{-v,--verbose}'[Print commands before running them]' \
                    '--agenix-bin[agenix executable to use]:path:_files' \
                    '*:root:_directories'
                  ;;
                discover-ssh-keys)
                  _arguments \
                    '(-n --dry-run)'{-n,--dry-run}'[Print intended changes without editing files]' \
                    '(-f --force)'{-f,--force}'[Update hosts that already have sshPublicKey(s)]' \
                    '(-c --continue)'{-c,--continue}'[Continue after failures]' \
                    '(-T --timeout)'{-T,--timeout}'[ssh-keyscan timeout in seconds]:seconds' \
                    '(-v --verbose)'{-v,--verbose}'[Print ssh-keyscan targets]' \
                    '*:host or hosts path:_directories'
                  ;;
                dependency-graph)
                  _arguments \
                    '--format[Output format]:format:(text mermaid svg dot json)' \
                    '(-o --output)'{-o,--output}'[Write output to file]:file:_files' \
                    '--host[Limit to host and dependencies]:host' \
                    '--reverse[With --host, show dependents instead of dependencies]' \
                    '--no-validate[Do not fail on missing refs/cycles]'
                  ;;
                packet)
                  _arguments \
                    '--path[Packet path]:path:(forward input)' \
                    '--from[Ingress interface/zone]:interface' \
                    '--to[Egress interface/zone]:interface' \
                    '--src[Source IP/CIDR]:address' \
                    '--dst[Destination IP/CIDR]:address' \
                    '--proto[Protocol]:proto:(tcp udp icmp icmpv6 ipv6-icmp any)' \
                    '--sport[Source port]:port' \
                    '--dport[Destination port]:port' \
                    '--ct-state[Conntrack state]:state:(new established related invalid)' \
                    '--ct-mark[Conntrack mark]:mark' \
                    '--mark[Packet meta/fw mark]:mark' \
                    '--tcp-flags[TCP flags, comma or space separated]:flags' \
                    '--json[Emit JSON]' \
                    '--examples[Show examples]' \
                    '--list-zones[List modeled VRF/NAT zones]' \
                    '--list-interfaces[List known interfaces/zones]' \
                    '--dump-model[Dump evaluated firewall model]'
                  ;;
              esac
              ;;
          esac
        }

        _lhflake "$@"
      '';

      lhflake = pkgs.stdenv.mkDerivation {
        name = "lhflake";
        src = script;
        nativeBuildInputs = [ pkgs.installShellFiles ];
        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin
          cp ${script}/bin/lhflake $out/bin/lhflake
          installShellCompletion --bash --name lhflake ${bashCompletion}
          installShellCompletion --zsh --name _lhflake ${zshCompletion}
          runHook postInstall
        '';
      };
    in
    {
      packages.lhflake = lhflake;
    };
}
