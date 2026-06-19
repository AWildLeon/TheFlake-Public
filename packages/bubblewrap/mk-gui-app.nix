{
  inputs,
  pkgs,
  mkNixPak,
}:

{
  package,
  binPath ? null,
  rwPaths ? [ ],
  roPaths ? [ ],
  extraConfig ? { },
}:

(mkNixPak {
  config =
    args@{ lib, sloth, ... }:
    {
      imports = [
        inputs.nixpak.nixpakModules.gui-base
        inputs.nixpak.nixpakModules.network
      ];

      config = lib.mkMerge [
        {
          app.package = package;

          bubblewrap = {
            sockets = {
              wayland = true;
              x11 = true;
              pipewire = true;
            };
            bind.dev = [
              "/dev/shm"
            ];
            # CEF/Electron apps need a writable /tmp for GPU-process IPC;
            # without it the GPU subprocess exits immediately on startup.
            # Use bind.rw (not tmpfs) so the X11 socket under /tmp/.X11-unix
            # remains accessible — a --tmpfs /tmp would overmount and hide it.
            bind.rw = [ "/tmp" ] ++ map (path: sloth.mkdir (sloth.concat' sloth.homeDir "/${path}")) rwPaths;
            bind.ro = map (path: sloth.concat' sloth.homeDir "/${path}") roPaths;

            env = {
              XDG_CURRENT_DESKTOP = sloth.env "XDG_CURRENT_DESKTOP";
            };
          };
        }
        (lib.optionalAttrs (binPath != null) {
          app.binPath = binPath;
        })
        (if lib.isFunction extraConfig then extraConfig args else extraConfig)
      ];
    };
}).config.env
