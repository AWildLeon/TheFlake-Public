# Global deployment dependency group definitions.
#
# Hosts join groups from their meta.nix with:
#   dependencyGroupMemberships = [ "home_route_reflectors" ];
#
# Other hosts reference a group from dependencies with:
#   dependencies = [ "#home_route_reflectors" ];
#
# The inventory collector expands `#group` references into the corresponding
# conditional dependencyGroups using the members discovered from host metadata.
{
  home_route_reflectors = {
    mode = "at_least_one";
    description = "Home BGP route reflectors; at least one must remain available for home routers.";
  };

  public_border_routers = {
    mode = "at_least_one";
    description = "Public AS213719 border routers; at least one border path must remain available.";
  };
}
