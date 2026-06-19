{ pkgs, mkGuiApp }:

mkGuiApp {
  package = pkgs.vesktop.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/vesktop \
        --add-flags "--disable-speech-api" \
        --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.xdg-utils ]}
    '';
  });
  rwPaths = [
    ".config/vesktop"
    ".cache/vesktop"
  ];
  extraConfig = { sloth, ... }: {
    bubblewrap.env.NIXOS_OZONE_WL = "1";
    # Open links on the host, outside the sandbox: xdg-open (added to PATH above)
    # routes through the xdg-desktop-portal OpenURI interface instead of trying
    # to spawn a handler inside the sandbox. Portal D-Bus talk access is already
    # granted by nixpak's gui-base module (org.freedesktop.portal.*).
    bubblewrap.env.NIXOS_XDG_OPEN_USE_PORTAL = "1";
    bubblewrap.bind.rw = [
      [
        (sloth.concat [
          "/run/user/"
          sloth.uid
          "/discord-tmp"
        ])
        "/tmp"
      ]
    ];
    dbus.policies = {
      "dev.vencord.Vesktop" = "own";
      "org.kde.StatusNotifierItem.*" = "own";
      "org.freedesktop.StatusNotifierItem.*" = "own";
      "org.kde.StatusNotifierWatcher" = "talk";
      "org.freedesktop.StatusNotifierWatcher" = "talk";
    };
  };
}
