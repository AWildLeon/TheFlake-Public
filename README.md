# NixOS Configurations

## ! WARNING: This README is Outdated !

This repository contains a comprehensive collection of NixOS system configurations and deployment tools for managing multiple machines in a personal infrastructure setup.

## Overview

This is a Nix flake-based configuration repository that provides:

- **Multi-machine NixOS configurations** - Declarative system configurations for various machines including servers, desktops, and specialized systems
- **Modular architecture** - Reusable modules for common functionality across different machine types
- **Automated deployment** - Integration with Colmena for remote deployment and nixos-anywhere for fresh installs
- **Role-based system organization** - Predefined roles for desktop, server, and specialized use cases

## Repository Structure

### 🖥️ Machine Configurations (`machines/`)

Individual machine configurations including:

- `bastion/` - Bastion/jump server
- `cdn/` - Content delivery network server
- `nas/` - Network attached storage server
- `realtox1/` - Production server
- `lh-pc/` - Desktop workstation
- And more...

### 📦 Modules (`modules/`)

Reusable configuration modules:

- **Core** - Base system configuration, locales, Nix settings
- **Network** - DNS and networking configurations
- **Security** - SSH, certificates, and hardening
- **Storage** - Disk configurations and bootloaders
- **System** - Shell environment and impermanence setup
- **User Management** - User account configurations

### 🎭 Roles (`roles/`)

Predefined system roles:

- **Desktop** - Complete desktop environment with X11/Plasma, gaming, media, office tools
- **Server** - Base server setup, Docker, Nginx, development tools

### 🚀 Deployment Tools

- **nixos-anywhere** - Templates for fresh system installations
- **nixos-generators** - Custom system image generation
- **Colmena** - Remote deployment and management

## Key Features

- **Impermanence** - Root filesystem is wiped on reboot for enhanced security
- **Secrets Management** - Encrypted secrets using agenix
- **Home Manager Integration** - User environment management
- **Hardware Support** - nixos-hardware integration for better hardware compatibility
- **Disk Management** - Declarative disk partitioning with disko

## Usage

This repository uses Nix flakes. To deploy a configuration:

```bash
# Deploy to a remote machine using Colmena
colmena apply --on <machine-name>

# Build a configuration locally
nix build .#nixosConfigurations.<machine-name>.config.system.build.toplevel

# Install on a fresh system with nixos-anywhere
nix run github:nix-community/nixos-anywhere -- --flake .#<machine-name> <target-host>
```

## Dependencies

This configuration relies on several excellent Nix community projects:

- [nixpkgs](https://github.com/NixOS/nixpkgs) - The Nix package collection
- [home-manager](https://github.com/nix-community/home-manager) - User environment management
- [disko](https://github.com/nix-community/disko) - Declarative disk partitioning
- [impermanence](https://github.com/nix-community/impermanence) - Stateless system setup
- [colmena](https://github.com/zhaofengli/colmena) - Remote deployment tool
- [agenix](https://github.com/ryantm/agenix) - Secrets management

## License

Copyright (c) 2025 Leon Hubrich. All rights reserved. See `license.md` for details.
