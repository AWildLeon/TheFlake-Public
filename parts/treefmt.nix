_:
let
  nix_excludes = [
    "hardware-configuration.nix"
  ];
in
{
  perSystem.treefmt = _: {
    programs = {
      shellcheck = {
        enable = true;
      };
      shfmt = {
        enable = true;
      };
      nixfmt = {
        enable = true;
        excludes = nix_excludes;
      };
      prettier = {
        enable = true;
      };
      statix = {
        enable = true;
        excludes = nix_excludes;
      };
      deadnix = {
        enable = true;
        excludes = nix_excludes;
        no-lambda-pattern-names = true;
      };
    };
  };
}
