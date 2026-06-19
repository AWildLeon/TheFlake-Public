_: {
  flake.diskoConfigurations =
    let
      defaultV1 = import ./default/v1/disk.nix;

      mk =
        {
          device,
          withDocker ? false,
          withSwap ? true,
          swapSize ? "1G",
        }:
        defaultV1 {
          inherit
            device
            withDocker
            withSwap
            swapSize
            ;
        };
    in
    {
      # expose the constructor too (optional)
      default-v1 = defaultV1;

      default-v1-sda = mk {
        device = "/dev/sda";
        withDocker = false;
      };
      default-v1-sda-docker = mk {
        device = "/dev/sda";
        withDocker = true;
      };
      default-v1-vda = mk {
        device = "/dev/vda";
        withDocker = false;
      };
      default-v1-vda-docker = mk {
        device = "/dev/vda";
        withDocker = true;
      };
      default-v1-sda-noswap = mk {
        device = "/dev/sda";
        withDocker = false;
        withSwap = false;
      };
      default-v1-vda-noswap = mk {
        device = "/dev/vda";
        withDocker = false;
        withSwap = false;
      };
    };
}
