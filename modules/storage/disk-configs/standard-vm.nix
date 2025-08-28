# Copyright (c) 2025 Leon Hubrich
# All rights reserved. See LICENSE for details.
#
# Standard VM disk configuration - Current Version Alias
# This file imports the current recommended version of the standard VM disk layout.
# Change the import below to upgrade all machines using this configuration.

{
  imports = [
    ./standard-vm-v1.nix # Current version - change to v2 when ready to upgrade
  ];
}
