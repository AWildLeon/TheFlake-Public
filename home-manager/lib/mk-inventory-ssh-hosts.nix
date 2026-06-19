{ lib, self }:
{
  hosts ? import (self + /tools/inventory/collect-meta.nix) { root = self + /hosts; },
  include ? (_: true),
  name ? (host: host.name),
  includeDefaultPorts ? false,
  extraMatchBlocks ? { },
  proxyCommand ? null,
}:
let
  inherit (builtins) filter listToAttrs;

  hasTarget = host: host.meta.deployment.targetHost or null != null;

  mkMatchBlock =
    host:
    let
      deployment = host.meta.deployment;
      port = deployment.sshPort or 22;
    in
    {
      inherit (host) name;
      value = {
        hostname = deployment.targetHost;
        user = deployment.sshUser or "root";
      }
      // lib.optionalAttrs (includeDefaultPorts || port != 22) {
        inherit port;
      }
      // lib.optionalAttrs (proxyCommand != null) {
        inherit proxyCommand;
      };
    };

  selectedHosts = filter (host: hasTarget host && include host) hosts;
in
(listToAttrs (map (host: (mkMatchBlock host) // { name = name host; }) selectedHosts))
// extraMatchBlocks
