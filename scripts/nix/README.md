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

## Building x86_64-darwin on Apple Silicon

If you're on an Apple Silicon (aarch64-darwin) Mac and want to build x86_64-darwin (Intel) binaries locally, you can use Rosetta 2 emulation.

### Setup

1. **Install Rosetta 2** (if not already installed):
   ```bash
   softwareupdate --install-rosetta
   ```

2. **Configure Nix to support x86_64-darwin**:

   Add to your Nix configuration:
   
   **For `/etc/nix/nix.conf` or `~/.config/nix/nix.conf`:**
   ```conf
   extra-platforms = x86_64-darwin
   ```
   
   **For Nix-Darwin or Home Manager:**
   ```nix
   nix.settings.extra-platforms = [ "x86_64-darwin" ];
   ```

3. **Build the x86_64-darwin package**:
   ```bash
   nix build .#packages.x86_64-darwin.percy-cli
   ```
   
   Or using the default package:
   ```bash
   nix build .#percy-cli --system x86_64-darwin
   ```

### How It Works

- Nix will use your aarch64 host to run x86_64 tools under Rosetta 2
- The build will produce a store path for x86_64-darwin (Intel binary)
- This allows you to build Intel macOS binaries locally without needing a separate Intel Mac

### Alternative: Remote Builder

If you have an Intel Mac (or CI runner) available, you can configure it as a remote Nix builder for faster, native x86_64-darwin builds:

```conf
builders = ssh://builder@intel-mac x86_64-darwin - 4 1 big-parallel,kvm
```

Then use the same build commands - Nix will automatically offload to the remote builder.

