# TheFlake - My NixOS Configurations

Production-ready NixOS modules, roles, and security configurations.

## ⚠️ Public Snapshot Repository

**This is an automated public snapshot** - not the main development branch. Only safe, reusable components are included. Customer configs, secrets, and proprietary code are excluded.

## 📁 Structure

```text
├── lib/                   # Utility functions and deployment helpers
├── modules/               # Reusable NixOS modules (core, services, security)
├── roles/                 # Pre-built system configurations (base, desktop, server)
├── hardening/            # Security hardening configurations
└── templates/            # Quick-start templates
```

Contains modules for core system config, services (nginx, traefik, databases), security hardening, and desktop environments.

---

Btw You can add a Machines folder and it would work like inside of my private flake (Autodiscovery).
