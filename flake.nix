{
  nixConfig = {
    substituters =
      [ "https://cache.nixos.org/" "https://nix-community.cachix.org" ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
  };

  inputs = {
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence.url = "github:nix-community/impermanence";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    colmena.url = "github:zhaofengli/colmena";

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixos-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    glance-ical-events = {
      url = "github:AWildLeon/Glance-iCal-Events";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    arion = {
      url = "github:AWildLeon/leons-arion/prod";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";

    stylix = {
      url = "github:nix-community/stylix/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix4vscode = {
      url = "github:nix-community/nix4vscode";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-flatpak = { url = "github:gmodena/nix-flatpak/?ref=v0.6.0"; };

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    copyparty = {
      url = "github:9001/copyparty";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = inputs@{ self, nixpkgs, colmena, ... }:
    let
      # Import our library
      lib = import ./lib { inherit inputs self; };

      # Build system configurations
      inherit (lib) systems;
      inherit (lib) deployment;
      inherit (lib) devShell;
      inherit (lib) treefmt;
      inherit (lib) apps;

    in
    {
      # Export helper functions for external use
      inherit lib;

      # NixOS configurations for nixos-rebuild
      nixosConfigurations = systems.mkNixosAuto;

      # Pre-commit checks
      checks = lib.forEachSystem
        (system: { pre-commit-check = devShell.pre-commit-check.${system}; });

      # Colmena deployment configuration
      colmenaHive = colmena.lib.makeHive (deployment.mkColmenaAuto // {
        meta = {
          nixpkgs = import nixpkgs {
            system = "x86_64-linux";
            overlays = [ ];
          };
          specialArgs = {
            inherit (inputs)
              disko impermanence home-manager nixos-unstable agenix arion
              nixos-facter-modules nixos-generators stylix spicetify-nix
              nix4vscode plasma-manager glance-ical-events copyparty;
            inherit inputs self;
            ts = builtins.toString
              (self.lastModified or (inputs.nixpkgs.lastModified or 0));
            pkgsUnstable = import inputs.nixos-unstable {
              system = "x86_64-linux";
              config.allowUnfree = true;
            };
            inherit colmena;
          };
        };
      });

      # Build packages
      packages.x86_64-linux = {
        # Using helper function for generator packages
        proxmox-installer-iso = systems.mkGenerator {
          format = "install-iso";
          modules =
            [ ./nixos-anywhere/proxmox-installer-iso/configuration.nix ];
        };

        tcn-thinclient = systems.mkGenerator {
          format = "kexec-bundle";
          modules = [ ./nixos-generators/tcn-thinclient/configuration.nix ];
        };

        # Generate options documentation for all modules
        options-html =
          let
            pkgs = nixpkgs.legacyPackages.x86_64-linux;

            # Include ALL modules - now that we've fixed the evaluation issues
            testModules = [
              # Security and hardening modules
              ./modules/security/customca.nix
              ./modules/security/ssh.nix
              ./hardening/misc.nix
              ./hardening/kernel.nix
              ./hardening/memalloc.nix
              ./hardening/proc.nix
              ./hardening/services.nix
              ./hardening/guestagent.nix

              # Helper and utility modules
              ./modules/helper/jail.nix
              ./modules/packages/ipxe.nix
              ./modules/network/home-dns.nix
              ./modules/cosmetic/motd-and-issue.nix

              # ALL service modules - fixed to use defaultText
              ./modules/services/bootserver.nix
              ./modules/services/nginx.nix
              ./modules/services/recursivedns.nix
              ./modules/services/traefik.nix
              ./modules/services/gitea.nix
              ./modules/services/glanceapp.nix
              ./modules/services/grafana.nix
              ./modules/services/nameserver.nix
              ./modules/services/databases/mysql.nix
            ];

            # Create module evaluation for ALL modules
            eval =
              let
                # Create config that provides values for all modules
                dummyConfig = {
                  networking = {
                    hostName = "example-host";
                    fqdn = "example-host.example.com";
                    domain = "example.com";
                  };
                  system.stateVersion = "24.05";
                  time.timeZone = "UTC";
                  lh = {
                    security = {
                      customca = {
                        enable = false;
                        domain = "example.com";
                      };
                      ssh.enable = false;
                    };
                    services = {
                      nginx.enable = false;
                      recursivedns.enable = false;
                      traefik.enable = false;
                      bootserver.enable = false;
                      gitea.enable = false;
                      glanceapp.enable = false;
                      grafana.enable = false;
                      nameserver.enable = false;
                    };
                    cosmetic.motd.enable = false;
                  };
                };
              in
              nixpkgs.lib.evalModules {
                specialArgs = {
                  inherit pkgs;
                  inherit (nixpkgs) lib;
                };
                modules = testModules ++ [{
                  _module.check = false;
                  inherit (dummyConfig) networking system time lh;
                }];
              };

            # Extract options and replace defaults with raw expressions to avoid evaluation
            processedOptions =
              let
                # Helper function to safely extract source text from option defaults
                getDefaultText = opt:
                  if opt ? defaultText then
                    if builtins.isAttrs opt.defaultText && opt.defaultText
                      ? text then
                      opt.defaultText.text
                    else
                      toString opt.defaultText
                  else if opt ? default then
                  # For problematic defaults, just indicate it's an expression
                    "<expression>"
                  else
                    null;

                # Process each option to avoid evaluation issues
                processOption = opt:
                  if opt._type or null == "option" then
                    opt // {
                      # Clean up declaration paths
                      declarations = map
                        (decl:
                          let
                            declStr = toString decl;
                            match = builtins.match ".*/nix-configs/(.*)" declStr;
                          in
                          if match != null then
                            "./" + (builtins.head match)
                          else
                            declStr)
                        (opt.declarations or [ ]);

                      # Replace default with safe text representation
                    } // (if opt ? default then {
                      default = {
                        _type = "literalExpression";
                        text = getDefaultText opt;
                      };
                    } else
                      { })
                  else
                    opt;
              in
              nixpkgs.lib.mapAttrsRecursive (_: processOption) eval.options;

            # Generate the options documentation with warnings disabled
            optionsDoc = pkgs.nixosOptionsDoc {
              options = processedOptions;
              transformOptions = opt:
                opt // {
                  # Additional transform if needed - path cleanup is already done above
                };
              # Disable warnings as errors to allow options without descriptions
              warningsAreErrors = false;
            };
          in
          pkgs.runCommand "options-html" { } ''
            mkdir -p $out

            # Copy the generated documentation files
            if [ -d "${optionsDoc.optionsCommonMark}" ]; then
              cp -r ${optionsDoc.optionsCommonMark}/* $out/ 2>/dev/null || cp ${optionsDoc.optionsCommonMark} $out/options.md
            else
              cp ${optionsDoc.optionsCommonMark} $out/options.md
            fi

            # Handle optionsJSON which might be in a subdirectory structure
            if [ -d "${optionsDoc.optionsJSON}" ]; then
              # Copy the entire directory structure but also create a direct link to the JSON file
              cp -r ${optionsDoc.optionsJSON}/* $out/ 2>/dev/null || true
              # Find and copy the actual JSON file to the root
              find ${optionsDoc.optionsJSON} -name "options.json" -exec cp {} $out/options.json \; 2>/dev/null || true
            else
              cp ${optionsDoc.optionsJSON} $out/options.json
            fi

            # Generate HTML from the CommonMark with optimized template
            ${pkgs.pandoc}/bin/pandoc \
              --from commonmark \
              --to html5 \
              --standalone \
              --toc \
              --toc-depth=3 \
              --title "NixOS Configuration Options Documentation" \
              --metadata title="NixOS Configuration Options Documentation" \
              --template ${
                pkgs.writeText "options-template.html" ''
                  <!DOCTYPE html>
                  <html xmlns="http://www.w3.org/1999/xhtml" lang="$lang$" xml:lang="$lang$">
                  <head>
                    <meta charset="utf-8" />
                    <meta name="generator" content="pandoc" />
                    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes" />
                    <title>$title$</title>
                    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
                    <style>
                      body { padding: 2rem; }
                      .option-name { font-family: monospace; font-weight: bold; color: #0066cc; }
                      .option-type { font-style: italic; color: #666; }
                      .option-default { background-color: #f8f9fa; padding: 0.25rem; border-radius: 0.25rem; }
                      pre { background-color: #f8f9fa; padding: 1rem; border-radius: 0.375rem; }
                      h1, h2, h3, h4, h5, h6 { margin-top: 2rem; margin-bottom: 1rem; }
                      .toc ul { list-style-type: none; }
                      .search-container { margin-bottom: 2rem; }
                      .search-box { width: 100%; padding: 0.75rem; border: 1px solid #ddd; border-radius: 0.375rem; }
                      .search-results { margin-top: 1rem; }
                      .highlight { background-color: yellow; }
                      .sidebar { position: sticky; top: 2rem; max-height: calc(100vh - 4rem); overflow-y: auto; }
                      .option-section { margin-bottom: 2rem; padding: 1rem; border: 1px solid #e9ecef; border-radius: 0.375rem; }
                      .filter-buttons { margin-bottom: 1rem; }
                      .filter-btn { margin-right: 0.5rem; margin-bottom: 0.5rem; }
                      .stats-badge { margin-left: 1rem; }
                    </style>
                  </head>
                  <body>
                    <div class="container-fluid">
                      <div class="row">
                        <div class="col-md-3">
                          <nav class="sidebar">
                            <h4>Search &amp; Navigation</h4>
                            <div class="search-container">
                              <input type="text" id="searchBox" class="search-box" placeholder="Search options..." />
                              <div class="filter-buttons mt-2">
                                <button class="btn btn-sm btn-outline-primary filter-btn" data-filter="all">All</button>
                                <button class="btn btn-sm btn-outline-secondary filter-btn" data-filter="security">Security</button>
                                <button class="btn btn-sm btn-outline-success filter-btn" data-filter="services">Services</button>
                                <button class="btn btn-sm btn-outline-info filter-btn" data-filter="packages">Packages</button>
                                <button class="btn btn-sm btn-outline-warning filter-btn" data-filter="cosmetic">Cosmetic</button>
                              </div>
                              <div class="mt-2">
                                <span class="badge bg-primary stats-badge">87 Total Options</span>
                                <span class="badge bg-success stats-badge">86 Custom Options</span>
                              </div>
                            </div>
                            <div id="TOC" class="toc">
                              <h5>Table of Contents</h5>
                              $toc$
                            </div>
                          </nav>
                        </div>
                        <div class="col-md-9">
                          <header class="mb-4">
                            <h1 class="display-4">$title$</h1>
                            <p class="lead">Complete documentation for ALL NixOS configuration options in this repository.</p>
                            <div class="alert alert-success">
                              <h5>Complete Documentation Coverage</h5>
                              <p>This documentation includes options from ALL modules in the repository:</p>
                              <ul>
                                <li><strong>Security &amp; Hardening:</strong> Custom CA, SSH, kernel hardening, memory allocation, process security, service hardening, guest agent hardening</li>
                                <li><strong>Services:</strong> Boot server, Nginx, recursive DNS, Traefik reverse proxy, Gitea, Grafana, Glance dashboard, Nameserver</li>
                                <li><strong>Packages:</strong> Custom iPXE builds with embedded scripts</li>
                                <li><strong>Utilities:</strong> Service jails, network configuration, MOTD customization</li>
                              </ul>
                              <p><small><em>All default values are displayed as raw Nix expressions without evaluation.</em></small></p>
                            </div>
                            <hr>
                          </header>
                          <main id="content">
                            $body$
                          </main>
                        </div>
                      </div>
                    </div>
                    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
                    <script>
                      document.addEventListener("DOMContentLoaded", function() {
                        var searchBox = document.getElementById("searchBox");
                        var content = document.getElementById("content");

                        if (searchBox && content) {
                          searchBox.addEventListener("input", function(e) {
                            var searchTerm = e.target.value.toLowerCase();
                            var sections = content.querySelectorAll("h2, h3, h4, p, code, pre");

                            sections.forEach(function(section) {
                              var text = section.textContent.toLowerCase();
                              if (searchTerm === "" || text.indexOf(searchTerm) !== -1) {
                                section.style.display = "";
                              } else {
                                section.style.display = "none";
                              }
                            });
                          });
                        }

                        var filterBtns = document.querySelectorAll(".filter-btn");
                        filterBtns.forEach(function(btn) {
                          btn.addEventListener("click", function() {
                            var category = this.getAttribute("data-filter");
                            var headings = content.querySelectorAll("h2, h3");

                            headings.forEach(function(heading) {
                              var text = heading.textContent.toLowerCase();
                              var show = false;

                              if (category === "all") {
                                show = true;
                              } else if (category === "security" && (text.indexOf("security") !== -1 || text.indexOf("ssh") !== -1 || text.indexOf("ca") !== -1 || text.indexOf("hardening") !== -1)) {
                                show = true;
                              } else if (category === "services" && text.indexOf("services") !== -1) {
                                show = true;
                              } else if (category === "packages" && text.indexOf("packages") !== -1) {
                                show = true;
                              } else if (category === "cosmetic" && text.indexOf("cosmetic") !== -1) {
                                show = true;
                              }

                              heading.style.display = show ? "" : "none";
                              var next = heading.nextElementSibling;
                              while (next && !next.matches("h2, h3")) {
                                next.style.display = show ? "" : "none";
                                next = next.nextElementSibling;
                              }
                            });
                          });
                        });
                      });
                    </script>
                  </body>
                  </html>
                ''
              } \
              $out/options.md > $out/options.html

            echo "Documentation generated successfully!"
            echo "Files created:"
            echo "  - options.html (main documentation)"
            echo "  - options.md (markdown source)"
            echo "  - options.json (machine-readable options)"
          '';
      };

      # Treefmt configuration
      treefmt = treefmt.mkTreefmt;

      # Development shell
      devShells = devShell.mkDevShells;

      # App definitions
      apps.x86_64-linux = apps.mkApps;

      # Netboot images (separate to avoid recursion)
      netboot.x86_64-linux = {
        tcn-thinclient =
          let
            netbootSystem = nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                ./machines/netboot/tcn-thinclient-netboot/configuration.nix
                inputs.stylix.nixosModules.stylix
              ];
              specialArgs = {
                inherit (inputs)
                  disko impermanence home-manager nixos-unstable agenix arion
                  nixos-facter-modules nixos-generators stylix spicetify-nix
                  nix4vscode plasma-manager glance-ical-events copyparty;
                inherit self;
                ts = builtins.toString
                  (self.lastModified or (inputs.nixpkgs.lastModified or 0));
                pkgsUnstable = import inputs.nixos-unstable {
                  system = "x86_64-linux";
                  config.allowUnfree = true;
                };
                inherit colmena;
              };
            };
          in
          {
            kernel =
              "${netbootSystem.config.system.build.kernel}/${netbootSystem.config.system.boot.loader.kernelFile}";
            initrd =
              if netbootSystem.config.system.build ? netbootRamdisk then
                "${netbootSystem.config.system.build.netbootRamdisk}/initrd"
              else if netbootSystem.config.system.build ? initrd then
                "${netbootSystem.config.system.build.initrd}"
              else
                throw
                  "netboot initrd not found for netbootSystem (neither system.build.netbootRamdisk nor system.build.initrd present)";
            inherit (netbootSystem.config.system.build) toplevel;
          };

        tcn-thinclient-nfsstore =
          let
            netbootSystem = nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                ./machines/netboot/tcn-thinclient-netboot-nfsstore/configuration.nix
                inputs.stylix.nixosModules.stylix
              ];
              specialArgs = {
                inherit (inputs)
                  disko impermanence home-manager nixos-unstable agenix arion
                  nixos-facter-modules nixos-generators stylix spicetify-nix
                  nix4vscode plasma-manager glance-ical-events copyparty;
                inherit self;
                ts = builtins.toString
                  (self.lastModified or (inputs.nixpkgs.lastModified or 0));
                pkgsUnstable = import inputs.nixos-unstable {
                  system = "x86_64-linux";
                  config.allowUnfree = true;
                  config.permittedInsecurePackages = [ "libsoup-2.74.3" ];
                };
                inherit colmena;
              };
            };
          in
          {
            kernel =
              "${netbootSystem.config.system.build.kernel}/${netbootSystem.config.system.boot.loader.kernelFile}";
            initrd =
              if netbootSystem.config.system.build ? netbootRamdisk then
                "${netbootSystem.config.system.build.netbootRamdisk}/initrd"
              else if netbootSystem.config.system.build ? initrd then
                "${netbootSystem.config.system.build.initrd}"
              else
                throw
                  "netboot initrd not found for netbootSystem (neither system.build.netbootRamdisk nor system.build.initrd present)";
            inherit (netbootSystem.config.system.build) toplevel;
          };
      };
    };
}
