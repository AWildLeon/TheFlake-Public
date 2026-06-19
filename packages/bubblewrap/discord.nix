{ pkgs, mkGuiApp }:

mkGuiApp {
  package = pkgs.vesktop.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/vesktop \
        --add-flags "--disable-speech-api"
    '';
  });
  rwPaths = [
    ".config/vesktop"
    ".cache/vesktop"
  ];
  extraConfig = { sloth, ... }: {
    bubblewrap.env.NIXOS_OZONE_WL = "1";
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
