# Nix Build Scripts

This directory contains Nix-specific build scripts and helpers.

## Current Contents

Currently empty. Nix build logic is primarily defined in `flake.nix` at the repository root.

## Related Files

- `flake.nix` - Main Nix flake configuration (repository root)
- `scripts/sign-macos.sh` - macOS signing script (used by both Nix and bash workflows)
- `.github/workflows/nix/executable.yml` - Nix-based CI workflow

