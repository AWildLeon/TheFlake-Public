{ lib, config, ... }:

with lib;

let
  cfg = config.lh.packages.ipxe;
in

{
  options.lh.packages.ipxe = {
    enable = mkEnableOption "Custom iPXE package with embedded boot script";

    bootServerUrl = mkOption {
      type = types.str;
      default = "http://\${next-server}";
      description = "URL of the PXE boot server. Uses iPXE's next-server variable by default.";
      example = "https://pxe.mydomain.com";
    };

    additionalTargets = mkOption {
      type = types.attrsOf (types.nullOr types.str);
      default = {
        "bin-x86_64-efi/snponly.efi" = "snponly.efi";
        "bin-x86_64-pcbios/undionly.kpxe" = "undionly.kpxe";
      };
      description = "Additional iPXE build targets";
      example = {
        "bin-x86_64-efi/ipxe.efi" = "ipxe.efi";
        "bin/undionly.kpxe" = "undionly.kpxe";
      };
    };

    additionalOptions = mkOption {
      type = types.listOf types.str;
      default = [
        "DOWNLOAD_PROTO_HTTP"
        "DOWNLOAD_PROTO_HTTPS"
        "CONSOLE_CMD"
        "REBOOT_CMD"
        "POWEROFF_CMD"
        "CONFIG_CMD"
        "IMAGE_PNG"
        "CONSOLE_FRAMEBUFFER"
      ];
      description = "Additional iPXE build options to enable";
      example = [ "PING_CMD" "NSLOOKUP_CMD" ];
    };
  };

  config = mkIf cfg.enable {
    nixpkgs.overlays = [
      (_final: prev: {
        ipxe = prev.ipxe.override {
          # Embed a boot script if enabled
          embedScript = builtins.toFile "boot.ipxe" ''
            #!ipxe
            :start
            dhcp || goto retry 
            
            chain --autofree --replace http://''${next-server}/boot.ipxe || goto fallback
            
            :fallback
            echo Netzwerkbooten Fehlgeschlagen Bitte den Admin Kontaktieren...
            shell
            reboot

            :retry
            echo DHCP failed, retrying...
            goto start
          '';
          # #   if cfg.embedScript then
          #     (
          #       builtins.toFile "boot.ipxe" (
          #         if cfg.customScript != null then cfg.customScript else ''
          #           #!ipxe

          #           ${optionalString cfg.showDebugInfo ''
          #             # Show iPXE version and build info
          #             echo iPXE Boot Loader - Einen Moment bitte...
          #             echo
          #             echo Build: ''${buildarch}-''${platform}
          #             echo MAC: ''${mac}
          #             echo
          #           ''}

          #           # Configure network interface
          #           dhcp

          #           ${optionalString cfg.showDebugInfo ''
          #             echo IP: ''${ip}
          #             echo Gateway: ''${gateway}
          #             echo DNS: ''${dns}
          #             echo
          #           ''}

          #           # Set boot server URL
          #           set boot-url ${cfg.bootServerUrl}

          #           # Try to chain load from boot server
          #           chain ''${boot-url}/stage2.ipxe || goto fallback

          #           # Fallback behavior
          #           :fallback
          #           ${if cfg.fallbackBehavior == "shell" then ''
          #             echo Netzwerk-Boot fehlgeschlagen, Bitte Administrator kontaktieren.
          #             echo Starte Shell...
          #             shell
          #           '' else if cfg.fallbackBehavior == "local-boot" then ''
          #             echo Network boot failed, attempting local boot
          #             sanboot --no-describe --drive 0x80 || exit
          #           '' else ''
          #             echo Network boot failed, powering off...
          #             poweroff
          #           ''}
          #         ''
          #       )
          #     ) else null;

          inherit (cfg) additionalTargets;
          inherit (cfg) additionalOptions;
        };
      })
    ];
  };
}
