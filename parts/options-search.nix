{ inputs, self, ... }:
{
  perSystem =
    {
      system,
      pkgs,
      ...
    }:
    let
      inherit (inputs.nuschtosSearch.packages.${system}) mkSearch;
    in
    {
      packages.options-search = mkSearch {
        title = "LH Flake Options";

        modules = [
          self.nixosModule.default
        ];

        urlPrefix = "http://localhost:8080/";

        baseHref = "/";

        specialArgs = {
          inherit inputs pkgs;
        };
      };
    };
}
