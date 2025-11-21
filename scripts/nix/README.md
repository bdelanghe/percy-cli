# Nix Build Scripts

This directory contains Nix-specific build scripts and helpers.

## Contents

- `build-windows.sh` - Windows-specific build script for Percy CLI
- `sign-macos.sh` - macOS signing and notarization script

## Related Files

- `flake.nix` - Main Nix flake configuration (repository root)
- `.github/workflows/nix/executable.yml` - Nix-based CI workflow

## Build Architecture

The Nix flake uses a **three-layer, cache-friendly architecture** to build the Percy CLI binary. This design maximizes Nix store and binary cache reuse while maintaining clean separation of concerns.

### Three-Layer Architecture

The build is split into three distinct layers, each with a specific purpose:

#### Layer 1: Patched Source (`patchedSrc`)

**Purpose**: Remove `"type": "module"` early so all consumers see consistent CJS semantics.

- **Input**: Upstream source (repository root)
- **Output**: Same tree with `"type": "module"` removed from relevant `package.json` files
- **Characteristics**:
  - Arch-agnostic (pure text manipulation)
  - Cache-friendly (only changes when source changes)
  - Pure derivation (no network, no environment dependencies)

**Why early?** The `"type": "module"` removal changes how Node resolves modules, so it must be visible to:
- Yarn during `yarn build`
- Node during `npm run build_cjs`
- Any runtime that loads these packages

#### Layer 2: Yarn Build (`nodeTree`)

**Purpose**: Build the complete JS project with dependencies and compiled output.

- **Input**: `patchedSrc` (Layer 1) + `yarn.lock`
- **Output**: Complete JS project ready for packaging (includes `node_modules`, `dist/`, built artifacts)
- **Characteristics**:
  - Arch-agnostic (if no native addons)
  - Highly cache-friendly (heaviest layer, reusable across systems)
  - Uses `mkYarnPackage` for offline, deterministic dependency resolution

**Build steps**:
- Installs dependencies via `mkYarnPackage` (offline, using `yarnConfigHook`)
- Runs `yarn build` to compile source
- Runs `npm run build_cjs` to convert ES6 to CommonJS
- Copies build artifacts to packages

#### Layer 3: Binary Packaging (`percy-cli`)

**Purpose**: Apply CLI-specific patches and wrap with `pkg` to create platform-specific binaries.

- **Input**: `nodeTree` (Layer 2)
- **Output**: Platform-specific binary executable (`percy`)
- **Characteristics**:
  - Per-system (pkg target varies by architecture)
  - Lightweight (just text edits + pkg invocation)
  - CLI-specific mutations isolated here

**Steps**:
- **patchPhase**: Applies CLI-specific patches:
  - Prepends `import { cli } from '@percy/cli';` to `packages/cli/dist/percy.js`
  - Injects `process.env.NODE_ENV = "executable";` into `packages/cli/bin/run.cjs`
- **installPhase**: Runs `pkg` to create the binary and normalizes output name

### Cache-Friendly Design

This layering provides maximum cache reuse:

1. **Layer 1 + Layer 2 are arch-agnostic**: If there are no native addons, the same build can be reused for all `*-linux` or `*-darwin` systems via binary cache
2. **Layer 1 + Layer 2 are stable**: Only change when `yarn.lock` or source changes
3. **Layer 3 is cheap**: Fast per-system derivation that just wraps the pre-built JS

### Patching Strategy

Patching is split across layers based on when and why it's needed:

- **Layer 1 (patchedSrc)**: Module semantics fix
  - Removes `"type": "module"` from package.json files
  - Must happen early so all build steps see consistent module resolution

- **Layer 3 (percy-cli)**: CLI-specific packaging hacks
  - Prepends import to `percy.js`
  - Injects NODE_ENV in `run.cjs`
  - These only affect the final executable, not the build process

### Reusable Scripts

The binary packaging logic is available as `scripts/percy-make-binary.sh` for reuse in CI or non-Nix release jobs:

```bash
./scripts/percy-make-binary.sh <pkg-target> <output-path>
```

This script:
- Runs `pkg` to create the binary
- Handles pkg's variable output naming
- Normalizes to a single output path

Nix uses the same logic inline in `installPhase` for consistency.

### Hash Calculation

When `yarn.lock` changes, the hash for `nodeTree` needs to be recalculated:

```bash
nix-build .#nodeTree 2>&1 | grep got:
```

Then update the hash in `flake.nix` if using `outputHash` or similar attributes.

