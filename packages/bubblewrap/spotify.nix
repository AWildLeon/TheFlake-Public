{ pkgs, mkGuiApp }:

mkGuiApp {
  package = pkgs.spotify;
  rwPaths = [
    ".config/spotify"
    ".cache/spotify"
  ];
  extraConfig = {
    bubblewrap.env.NIXOS_OZONE_WL = "1";
    # Private /tmp so Spotify's IPC sockets and tmp files don't leak to the host.
    # tmpfs comes after bind.ro in nixpak's arg order, so it overmounts both the
    # host /tmp bind (from mk-gui-app) and the X11 socket bind (from sockets.x11).
    # The GPU subprocess uses /dev/dri directly and has no X11 socket fds, so
    # hiding the X11 socket under the tmpfs is safe.
    bubblewrap.tmpfs = [ "/tmp" ];
    dbus.policies = {
      "com.spotify.Client" = "own";
      "org.mpris.MediaPlayer2.spotify" = "own";
    };
  };
}
