{ lib, ... }:
{
  # KDE caches the set of available .desktop entries in its sycoca database and
  # only notices new/changed entries when that cache is rebuilt. A Home Manager
  # switch relinks share/applications but does not refresh the cache, so freshly
  # installed launchers (e.g. the bubblewrapped GUI apps) don't appear in the
  # start menu until a relog or a manual `kbuildsycoca6`. Rebuild it right after
  # the new generation is linked so entries show up immediately.
  #
  # This is a standalone (non-NixOS) Home Manager setup, so kbuildsycoca6 comes
  # from the host's KDE install rather than nixpkgs; guard on its presence so the
  # hook is a no-op on hosts without Plasma. `--noincremental` forces a full
  # rebuild and, if a session bus is reachable, signals running Plasma to reload.
  home.activation.rebuildKdeSycoca = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if command -v kbuildsycoca6 >/dev/null 2>&1; then
      kbuildsycoca6 --noincremental || true
    fi
  '';
}
