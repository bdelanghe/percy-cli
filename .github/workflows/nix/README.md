# Nix Workflows

This directory contains GitHub Actions workflows that use Nix for building executables.

## Workflows

### `executable.yml`

Builds Percy CLI executables using Nix for Linux and macOS, with separate Windows build using bash scripts.

**Features:**
- Multi-architecture support (x86_64, aarch64) for Linux and macOS
- Nix-based builds for deterministic, reproducible builds
- Separate signing jobs for macOS binaries
- Windows builds using `scripts/nix/build-windows.sh`

**Trigger:** Runs on release publication

## Related Files

- `flake.nix` - Nix flake configuration (repository root)
- `scripts/nix/build-windows.sh` - Windows build script
- `scripts/nix/sign-macos.sh` - macOS signing script

