# Nix Build System for Percy CLI

This directory contains Nix-specific build configuration for building the Percy CLI binary using Bun.

## Overview

The build uses Bun to manage Node.js dependencies and build the Percy CLI monorepo. Bun reads `bun.lockb` (or generates it) and installs dependencies directly, providing fast, reproducible builds with native workspace support.

## Architecture

The build follows a multi-layer architecture:

1. **Layer 1: Patched Source** (`nix/src-patched.nix`)
   - Removes `"type": "module"` declarations from package.json files
   - Ensures consistent CommonJS semantics throughout the build

2. **Layer 2: Node Tree** (`flake.nix` - nodeTree)
   - Uses Bun to install dependencies from `bun.lockb`
   - Includes all devDependencies (babel, etc.)
   - Runs `bun run build` to compile all packages using Bun's workspace support
   - Runs `babel` to convert ES6 to CommonJS (if needed)

3. **Layer 3: Prepared CLI** (`nix/prepared-cli.nix`)
   - Applies CLI-specific patches for pkg packaging
   - Patches `percy.js` imports and `NODE_ENV`

4. **Layer 4: Binary** (`nix/pkg-wrapper.nix`)
   - Uses `pkg` to create platform-specific binaries
   - Supports: x86_64-linux, aarch64-linux, x86_64-darwin, aarch64-darwin

## How Bun Works

Bun is integrated directly in `flake.nix` using `stdenv.mkDerivation`:
- Installs dependencies using `bun install` (reads or generates `bun.lockb`)
- Uses Bun's native workspace support to build all packages
- Provides binaries from `node_modules/.bin` in the build environment
- Faster than traditional package managers (10-100x faster installs)

The build phase in `flake.nix` runs:
1. `bun install` to install all dependencies
2. `bun run build` to build all packages using workspace support
3. `babel` for CJS conversion (if needed)

## Building

### Build the binary for your system:
```bash
nix build
```

### Build for a specific system:
```bash
nix build .#percy-cli
```

### Build all layers:
```bash
nix build .#src-patched
nix build .#node-tree
nix build .#prepared-cli
nix build .#percy-cli
```

## Running Checks

Run all checks (builds all layers and verifies binary):
```bash
nix flake check
```

This will:
- Build all layers (src-patched, node-tree, prepared-cli, percy-cli)
- Verify the binary exists and is executable
- Run a smoke test (--version or --help)

### Run specific checks:
```bash
nix build .#checks.aarch64-darwin.binary_exists
nix build .#checks.aarch64-darwin.binary_smoke_test
```

## Updating Dependencies

When dependencies change:

1. Update `bun.lockb` (if not committed):
   ```bash
   bun install
   ```

2. Rebuild:
   ```bash
   nix build
   ```

Bun will automatically detect changes and rebuild `node_modules` accordingly. For Nix reproducibility, consider committing `bun.lockb` to version control.

## Troubleshooting

### Bun not found
If you see "bun not found" errors:
- Ensure Bun is available in nixpkgs for your system
- Check that `nativeBuildInputs` includes `bun` in `flake.nix`
- Verify Bun is installed in the dev shell: `nix develop`

### Lockfile issues
If `bun.lockb` doesn't exist:
- Bun will generate it automatically during `bun install`
- For reproducible builds, commit `bun.lockb` to version control
- Use `bun install --frozen-lockfile` in CI/Nix builds

### Build failures
- Check the build logs: `nix log /nix/store/...`
- Verify all source files are present
- Ensure `bun.lockb` is up to date (or let Bun generate it)
- Check that workspace packages are correctly configured

### Native module issues
If you encounter native module issues:
- Verify the native module is compatible with Bun
- Check that platform-specific packages (e.g., `@nx/nx-darwin-arm64`) are included
- Ensure Bun is using the correct Node.js version for compatibility

## Files

- `flake.nix` - Main flake configuration with Bun integration
- `nix/src-patched.nix` - Source patching layer
- `nix/prepared-cli.nix` - CLI preparation layer
- `nix/pkg-wrapper.nix` - pkg binary wrapper
- `nix/percy-config.nix` - Build configuration (versions, targets)
- `nix/dev-shell.nix` - Development shell with Bun

## Related Documentation

- [Bun Documentation](https://bun.sh/docs)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
- [Percy CLI Development Guide](../packages/cli/README.md)
