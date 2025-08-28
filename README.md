# TheFlake (Public)

This is the **public version** of my personal Nix flake.  
It contains the overall structure, modules, and examples I use to manage NixOS systems — but with all private content stripped out.

## About

TheFlake is my "single source of truth" for configuring and managing machines.  
It is built around:

- **NixOS & flakes** for reproducible system configurations
- **Home Manager** for user-level setup
- **Custom modules** for services, hardening, and automation

## Disclaimer ⚠️

- **This repo is 100% WIP.**
- Anything here may change or break at any time.
- Don’t expect stability or backwards compatibility.

I keep this public mainly to **share ideas and structure**, not to provide a polished or production-ready flake.

## What’s different here?

This repo is a **sanitized version** of my private flake.  
Omitted or stripped out content includes:

- Secrets & credentials
- Private network details (ASN, BGP, etc.)
- **All host/machine configurations**
- Experimental/WIP modules that aren’t meant to be public

The focus is on showing _how_ I structure things, not a fully working infra.

## Usage

You’re welcome to explore and adapt ideas from here into your own flake.  
Some modules may reference things that aren’t included in this public version — so expect to adapt them.
