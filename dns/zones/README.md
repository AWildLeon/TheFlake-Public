# dns/zones/

Each DNS zone lives in `dns/zones/<domain>/zone.nix` and is built with
`nix-community/dns.nix`. `dns/dns-inventory.nix` walks this directory live at
evaluation time, so a new zone directory is picked up automatically — no codegen.

A `zone.nix` is a function `{ inputs, lh, ... }: ...` returning a zone built from
the helpers in `dns/helpers/` and the shared defaults in `dns/defaults/`
(SOA/NS/CAA, plus optional mail bundles).

Sync zones to the Technitium server with `lhflake technitium-zone-sync`.
Never hand-edit SOA serials — the sync manages them automatically.

This template ships with no concrete zones — drop your own here.
