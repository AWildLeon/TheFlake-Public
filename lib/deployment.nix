# Deployment configurations (Colmena)
{ inputs, self }:
let
  inherit (inputs) nixpkgs;
  hostDiscovery = import ./host-discovery.nix { inherit inputs self; };

  # Helper function to create a Colmena deployment configuration
  mkColmenaDeployment =
    { hostname
    , targetHost
    , targetPort ? 22
    , targetUser ? "root"
    , tags ? [ "server" ]
    , keys ? { }
    , modules ? [ ]
    , withDisko ? false
    , withHomeManager ? true
    , withNixFlatpak ? false
    , withImpermanence ? false
    }: {
      deployment = {
        inherit targetHost targetPort targetUser tags;
      } // (nixpkgs.lib.optionalAttrs (keys != { }) { inherit keys; });
      imports = [
        (hostDiscovery.machineConfig hostname)
        inputs.stylix.nixosModules.stylix
      ] ++ (nixpkgs.lib.optionals withDisko [ inputs.disko.nixosModules.disko ])
      ++ (nixpkgs.lib.optionals withNixFlatpak
        [ inputs.nix-flatpak.nixosModules.nix-flatpak ])
      ++ (nixpkgs.lib.optionals withImpermanence
        [ inputs.impermanence.nixosModules.impermanence ])
      ++ (nixpkgs.lib.optionals withHomeManager
        [ inputs.home-manager.nixosModules.home-manager ]) ++ modules;
    };

  # Auto-generated Colmena entries using vars.nix files
  mkColmenaAuto = builtins.listToAttrs (builtins.map
    (h:
      let
        hostVars = hostDiscovery.loadHostVars h;
        deployConfig = hostVars.deployment;
      in
      {
        name = h;
        value = mkColmenaDeployment ({ hostname = h; } // deployConfig);
      })
    hostDiscovery.hosts);

in
{ inherit mkColmenaDeployment mkColmenaAuto; }
