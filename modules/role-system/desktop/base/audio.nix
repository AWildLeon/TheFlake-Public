{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.lh.desktop.audio;

  rnnoisePlugin = "${pkgs.rnnoise-plugin}/lib/ladspa/librnnoise_ladspa.so";

  rnnoiseModule = {
    name = "libpipewire-module-filter-chain";
    args = {
      "node.description" = "Noise Canceling source";
      "media.name" = "Noise Canceling source";

      "filter.graph" = {
        nodes = [
          {
            type = "ladspa";
            name = "rnnoise";
            plugin = rnnoisePlugin;
            label = "noise_suppressor_" + cfg.noiseCancel.inputType;
            control = {
              "VAD Threshold (%)" = cfg.noiseCancel.vadThreshold;
              "VAD Grace Period (ms)" = cfg.noiseCancel.vadGraceMs;
              "Retroactive VAD Grace (ms)" = cfg.noiseCancel.retroGraceMs;
            };
          }
        ];
      };

      "capture.props" = {
        "node.name" = "capture.rnnoise_source";
        "node.passive" = true;
        "audio.rate" = cfg.noiseCancel.rate;
      };

      "playback.props" = {
        "node.name" = "rnnoise_source";
        "media.class" = "Audio/Source";
        "audio.rate" = cfg.noiseCancel.rate;
      };
    };
  };
in
{
  options.lh.desktop.audio = {
    enable = lib.mkEnableOption "Desktop audio stack via PipeWire";

    noiseCancel = {
      enable = lib.mkEnableOption "RNNoise virtual microphone source";
      inputType = lib.mkOption {
        type = lib.types.enum [
          "mono"
          "stereo"
        ];
        default = "mono";
        description = "Input type for the RNNoise plugin.";
      };

      vadThreshold = lib.mkOption {
        type = lib.types.float;
        default = 50.0;
        description = "RNNoise VAD threshold in percent.";
      };

      vadGraceMs = lib.mkOption {
        type = lib.types.int;
        default = 200;
        description = "VAD grace period in milliseconds.";
      };

      retroGraceMs = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = "Retroactive VAD grace in milliseconds.";
      };

      rate = lib.mkOption {
        type = lib.types.int;
        default = 48000;
        description = "Sample rate for the virtual source.";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # 1) Baseline PipeWire stack
      {
        services.pulseaudio.enable = false;
        security.rtkit.enable = true;

        services.pipewire = {
          enable = true;
          alsa.enable = true;
          alsa.support32Bit = true;
          pulse.enable = true;
          jack.enable = true;
          wireplumber.enable = true;
        };
      }

      # 2) Optional RNNoise graph
      (lib.mkIf cfg.noiseCancel.enable {
        services.pipewire.extraConfig.pipewire."99-input-denoising" = {
          "context.modules" = [ rnnoiseModule ];
        };
      })
    ]
  );
}
