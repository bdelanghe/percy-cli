# Nix Build System for Percy CLI

This directory contains Nix-specific build configuration for building the Percy CLI binary using Bun.

## Overview

The build uses Bun to manage Node.js dependencies and build the Percy CLI monorepo. The Nix integration uses `bun2nix` (from nix-community) to provide offline, reproducible builds. Bun reads `bun.lockb` and installs dependencies from a pre-fetched offline cache, providing fast, reproducible builds with native workspace support.

## Architecture

The build follows a multi-layer architecture:

1. **Layer 1: Patched Source** (`nix/src-patched.nix`)
   - Removes `"type": "module"` declarations from package.json files
   - Ensures consistent CommonJS semantics throughout the build

2. **Layer 2: Node Tree** (`default.nix` - nodeTree)
   - Uses `bun2nix` to fetch dependencies offline from `bun.nix`
   - Uses Bun to install dependencies from `bun.lockb` using offline cache
   - Includes all devDependencies (babel, etc.)
   - Runs `bun run build_cjs` to compile all packages using Bun's workspace support

3. **Layer 3: Prepared CLI** (`nix/prepared-cli.nix`)
   - Applies CLI-specific patches for pkg packaging
   - Patches `percy.js` imports and `NODE_ENV`

4. **Layer 4: Binary** (`nix/pkg-wrapper.nix`)
   - Uses `pkg` to create platform-specific binaries
   - Supports: x86_64-linux, aarch64-linux, x86_64-darwin, aarch64-darwin

## How bun2nix Works

The build uses `bun2nix` (from nix-community) to provide offline, reproducible builds:

1. **bun.nix**: Pre-generated file (committed to version control) that contains all dependency fetch URLs and hashes
2. **bun2nix.fetchBunDeps**: Fetches all dependencies offline using the information in `bun.nix`
3. **bun2nix.hook**: Sets up Bun to use the offline cache during `bun install`
4. **Bun install**: Installs dependencies from the offline cache (no network access needed)
5. **Bun build**: Builds all packages using Bun's native workspace support

The build phase in `default.nix` runs:
1. `bun install --frozen-lockfile` (uses offline cache via bun2nix.hook)
2. `bun run build_cjs` to build all packages using workspace support
3. `babel` for CJS conversion (if needed)

This provides:
- **Offline builds**: No network access required during Nix builds
- **Reproducibility**: All dependencies are pinned with hashes
- **Speed**: Bun's fast installs combined with Nix's binary cache

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

When dependencies change, you can use Nix apps to generate the required lockfiles:

### Using Nix Apps (Recommended)

1. Update both lockfiles at once:
   ```bash
   nix run .#update-lockfiles
   ```

2. Or update them separately:
   ```bash
   # Generate bun.lockb
   nix run .#bun-install
   
   # Generate bun.nix from bun.lockb
   nix run .#bun2nix-generate
   ```

3. Commit both files:
   ```bash
   git add bun.lockb bun.nix
   git commit -m "Update dependencies"
   ```

4. Rebuild:
   ```bash
   nix build
   ```

### Using Bun Directly

Alternatively, you can use Bun directly:

1. Update `bun.lockb`:
   ```bash
   bun install
   ```

2. Regenerate `bun.nix`:
   ```bash
   bunx bun2nix -o bun.nix
   ```

3. Commit both files:
   ```bash
   git add bun.lockb bun.nix
   git commit -m "Update dependencies"
   ```

**Important**: Both `bun.lockb` and `bun.nix` must be committed to version control for reproducible Nix builds. The `bun.nix` file should be generated manually (not during the build process) to ensure reproducibility.

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

If `bun.nix` doesn't exist or is outdated:
- Regenerate it using Nix: `nix run .#bun2nix-generate`
- Or manually: `bunx bun2nix -o bun.nix`
- Commit the updated `bun.nix` file
- The build will fail if `bun.nix` is missing or doesn't match `bun.lockb`

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

- `flake.nix` - Main flake configuration with bun2nix integration
- `default.nix` - Main package definition using bun2nix
- `bun.nix` - Pre-generated dependency cache (committed to version control)
- `bun.lockb` - Bun's binary lockfile (committed to version control)
- `nix/src-patched.nix` - Source patching layer
- `nix/prepared-cli.nix` - CLI preparation layer
- `nix/pkg-wrapper.nix` - pkg binary wrapper
- `nix/percy-config.nix` - Build configuration (versions, targets)
- `nix/dev-shell.nix` - Development shell with Bun

## Related Documentation

- [Bun Documentation](https://bun.sh/docs)
- [bun2nix Documentation](https://github.com/nix-community/bun2nix)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
- [Percy CLI Development Guide](../packages/cli/README.md)
