# Nix Build System for Percy CLI

This directory contains Nix-specific build configuration for building the Percy CLI binary using `dream2nix`.

## Overview

The build uses `dream2nix` to manage Node.js dependencies and build the Percy CLI monorepo. Dream2nix reads `yarn.lock` directly and builds `node_modules` in the Nix store, providing better reproducibility and handling of native dependencies compared to `mkYarnPackage`.

## Architecture

The build follows a multi-layer architecture:

1. **Layer 1: Patched Source** (`nix/src-patched.nix`)
   - Removes `"type": "module"` declarations from package.json files
   - Ensures consistent CommonJS semantics throughout the build

2. **Layer 2: Node Tree** (`flake.nix` - nodeTree)
   - Uses `dream2nix` to build `node_modules` from `yarn.lock`
   - Includes all devDependencies (lerna, babel, etc.)
   - Runs `lerna run build` to compile all packages
   - Runs `babel` to convert ES6 to CommonJS

3. **Layer 3: Prepared CLI** (`nix/prepared-cli.nix`)
   - Applies CLI-specific patches for pkg packaging
   - Patches `percy.js` imports and `NODE_ENV`

4. **Layer 4: Binary** (`nix/pkg-wrapper.nix`)
   - Uses `pkg` to create platform-specific binaries
   - Supports: x86_64-linux, aarch64-linux, x86_64-darwin, aarch64-darwin

## How Dream2nix Works

Dream2nix is configured in `flake.nix` to:
- Read `yarn.lock` directly (translator: `yarn-lock`)
- Include devDependencies (needed for build tools like lerna, babel)
- Build node_modules in the Nix store
- Provide binaries from `node_modules/.bin` in the build environment

The configuration is in `nix/dream2nix-config.nix` and is used via `dream2nix.lib.evalModules`.

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

When `yarn.lock` changes:

1. Update the flake lock:
   ```bash
   nix flake update dream2nix
   ```

2. Rebuild:
   ```bash
   nix build
   ```

Dream2nix will automatically detect changes in `yarn.lock` and rebuild `node_modules` accordingly.

## Troubleshooting

### Lerna not found
If you see "lerna not found" errors:
- Ensure `includeDevDependencies = true` in dream2nix configuration
- Check that `yarn.lock` includes lerna in devDependencies
- Verify dream2nix is building node_modules correctly

### Native module issues
Dream2nix handles native modules better than mkYarnPackage, but if you encounter issues:
- Check that the native module is in `yarn.lock`
- Verify the platform-specific package (e.g., `@nx/nx-darwin-arm64`) is included
- Ensure dream2nix is using the correct Node.js version

### Build failures
- Check the build logs: `nix log /nix/store/...`
- Verify all source files are present
- Ensure yarn.lock is up to date

## Files

- `flake.nix` - Main flake configuration with dream2nix integration
- `nix/dream2nix-config.nix` - Dream2nix module configuration
- `nix/src-patched.nix` - Source patching layer
- `nix/prepared-cli.nix` - CLI preparation layer
- `nix/pkg-wrapper.nix` - pkg binary wrapper
- `nix/percy-config.nix` - Build configuration (versions, targets)
- `nix/dev-shell.nix` - Development shell

## Related Documentation

- [Dream2nix Documentation](https://dream2nix.dev/)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
- [Percy CLI Development Guide](../packages/cli/README.md)

