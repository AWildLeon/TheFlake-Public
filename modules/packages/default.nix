{ pkgsUnstable, ... }:
{
  imports = [ ./ipxe.nix ];

  nixpkgs.overlays = [
    # Technitium DNS Server Library overlay
    (_final: _prev: {
      inherit (pkgsUnstable) technitium-dns-server-library;
    })

    # Technitium DNS Server overlay
    (_final: _prev: {
      technitium-dns-server = pkgsUnstable.technitium-dns-server.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./dnssec-do-bit-fix.patch ];
      });
    })
  ];
}
