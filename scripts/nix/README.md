# Nix Build Scripts

This directory contains Nix-specific build scripts and helpers.

## Contents

- `build-windows.sh` - Windows-specific build script for Percy CLI
- `sign-macos.sh` - macOS signing and notarization script

## Related Files

- `flake.nix` - Main Nix flake configuration (repository root)
- `.github/workflows/nix/executable.yml` - Nix-based CI workflow

## Build Architecture

The Nix flake uses `mkYarnPackage` to build the Percy CLI binary. This approach provides better reproducibility and simplifies dependency management compared to manual yarn installation.

### mkYarnPackage Approach

The build process uses `mkYarnPackage` to create a fixed-output derivation for `node_modules`. This provides several benefits:

1. **Fixed-output derivation**: `node_modules` is built as a deterministic, reproducible derivation
2. **Automatic offline cache**: `mkYarnPackage` automatically sets up `yarnConfigHook` for offline installation
3. **Simplified dependency management**: No manual cache setup or yarn install steps required

### Build Flow

1. **yarnPackage derivation** (`mkYarnPackage`):
   - Takes the source code and `yarn.lock` file
   - Builds `node_modules` as a fixed-output derivation
   - Handles offline cache automatically via `yarnConfigHook`
   - Produces a derivation with `node_modules` available at `${yarnPackage}/node_modules`

2. **percy-cli derivation**:
   - **patchPhase**: Removes `"type": "module"` from package.json files (except dom and sdk-utils packages)
   - **buildPhase**:
     - Symlinks `node_modules` from `yarnPackage` into the build directory
     - Runs `yarn build` to build the project
     - Applies custom patches (prepends import to percy.js, injects NODE_ENV)
     - Runs `npm run build_cjs` to convert ES6 to CommonJS
   - **installPhase**:
     - Uses `npx pkg` to create the binary executable
     - Sets `NODE_PATH` to ensure pkg can resolve dependencies
     - Copies the resulting binary to `$out/bin/percy`

### Patching Strategy

Custom patching is handled in separate phases:

- **patchPhase** (before build): Removes `"type": "module"` from package.json files. This runs before the build and affects the source that gets built.
- **buildPhase** (after yarn build): Applies file modifications:
  - Prepends `import { cli } from '@percy/cli';` to `packages/cli/dist/percy.js`
  - Injects `process.env.NODE_ENV = "executable";` into `packages/cli/bin/run.cjs`

### node_modules Derivation

The `node_modules` tree is built once by `mkYarnPackage` and reused in the main derivation. This ensures:
- Dependencies are installed deterministically
- No network access is needed during the build (offline mode)
- The same `node_modules` structure is used consistently

The symlink in `buildPhase` makes the derived `node_modules` available to yarn and npm commands, while `NODE_PATH` in `installPhase` ensures pkg can resolve dependencies when bundling.

### Hash Calculation

When `yarn.lock` changes, the hash for `yarnPackage` needs to be recalculated. To get the new hash:

```bash
nix-build .#yarnPackage 2>&1 | grep got:
```

Then update the hash in `flake.nix` (if using `outputHash` or similar attributes).

