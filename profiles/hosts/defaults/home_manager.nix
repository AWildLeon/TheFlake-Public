{
  inputs,
  pkgsUnstable,
  ...
}:
{
  home-manager = {
    useGlobalPkgs = true;
    backupFileExtension = "hm-bak-${inputs.self.shortRev or inputs.self.dirtyShortRev or "dirty"}";
    sharedModules = [ inputs.self.homeModules.default ];
    extraSpecialArgs = {
      inherit pkgsUnstable inputs;
      inherit (inputs.self) lh;
    };
  };
}
