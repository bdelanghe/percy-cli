# Nix Build Scripts

This directory contains Nix-specific build scripts and helpers.

## Contents

- `build-windows.sh` - Windows-specific build script for Percy CLI
- `sign-macos.sh` - macOS signing and notarization script

## Related Files

- `flake.nix` - Main Nix flake configuration (repository root)
- `.github/workflows/nix/executable.yml` - Nix-based CI workflow

## Quick Start

Two CLI packaging options are available:

```bash
# Option A: Nix-wrapped Node (simpler, works with ESM directly)
nix build .#percy-cli-node

# Option B: Bun-compiled binary (true native binary, default)
nix build .#percy-cli
# or simply:
nix build
```

Both produce a `percy` executable in `./result/bin/percy`.

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
- Bun during `bun run build`
- Any runtime that loads these packages

#### Layer 2: Bun Build (`nodeTree`)

**Purpose**: Build the complete JS project with dependencies and compiled output.

- **Input**: `patchedSrc` (Layer 1) + `bun.lockb` (or generates it)
- **Output**: Complete JS project ready for compilation (includes `node_modules`, `dist/`, built artifacts)
- **Characteristics**:
  - Arch-agnostic (if no native addons)
  - Highly cache-friendly (heaviest layer, reusable across systems)
  - Uses Bun with offline cache for deterministic dependency resolution

**Build steps**:
- Installs dependencies via Bun (offline, using local registry server with offline cache)
- Runs `bun run build` to compile source using Bun's bundler (ESM output)
- Builds all packages in the monorepo as ESM modules

#### Layer 3: CLI Binary Packaging

Two options are available for packaging the CLI:

**Option A: Nix-Wrapped Node (`percy-cli-node`)**

**Purpose**: Simple wrapper that runs Node on the built ESM entrypoint.

- **Input**: `nodeTree` (Layer 2)
- **Output**: Shell script that invokes Node on the ESM entrypoint
- **Characteristics**:
  - Simple and straightforward
  - Works directly with ESM output from `bun build`
  - Requires Node.js in the Nix store (but not installed on user's system)
  - No binary compilation step

**Steps**:
- Creates a shell script that runs `${nodejs}/bin/node ${nodeTree}/packages/cli/dist/index.js "$@"`
- No build phase needed - just wraps the existing ESM output

**Option B: Bun-Compiled Binary (`percy-cli`)**

**Purpose**: Compile the CLI into a standalone native binary using Bun's compile feature.

- **Input**: `nodeTree` (Layer 2)
- **Output**: Platform-specific native binary executable (`percy`)
- **Characteristics**:
  - Per-system (compiled for target architecture)
  - Self-contained (includes Bun runtime)
  - True native binary (not a Node.js wrapper)
  - No external runtime dependencies

**Steps**:
- **buildPhase**: Runs `bun build --compile` on `packages/cli/src/bin.js` to create a standalone executable
- **installPhase**: Copies the compiled binary to `$out/bin/percy` and sets executable permissions

**Which to use?**

- **Option A (`percy-cli-node`)**: Simpler, works directly with ESM builds, good for development and Nix-native workflows
- **Option B (`percy-cli`)**: True standalone binary, no runtime dependencies, better for distribution outside Nix

The default package is `percy-cli` (Option B) for backward compatibility.

### Cache-Friendly Design

This layering provides maximum cache reuse:

1. **Layer 1 + Layer 2 are arch-agnostic**: If there are no native addons, the same build can be reused for all `*-linux` or `*-darwin` systems via binary cache
2. **Layer 1 + Layer 2 are stable**: Only change when `bun.lockb` or source changes
3. **Layer 3 is cheap**: Fast per-system derivation that just wraps the pre-built JS

### Patching Strategy

Patching is split across layers based on when and why it's needed:

- **Layer 1 (patchedSrc)**: Module semantics fix
  - Removes `"type": "module"` from package.json files
  - Must happen early so all build steps see consistent module resolution

- **Layer 3 (percy-cli)**: Binary compilation
  - Uses Bun's native `--compile` feature to create a standalone executable
  - No additional patching needed - Bun handles bundling and runtime embedding

### Binary Packaging Options

Two packaging options are available:

**Option A: Nix-Wrapped Node**

The simplest approach - wraps the ESM output with a Node.js script:

```bash
# Build the Nix-wrapped Node version
nix build .#percy-cli-node

# The result is a shell script that runs Node on the ESM entrypoint
./result/bin/percy --version
```

**Option B: Bun-Compiled Binary**

Creates a true native binary using Bun's compile feature:

```bash
# Build the Bun-compiled binary
nix build .#percy-cli

# Or use the default (same as percy-cli)
nix build

# The result is a standalone native binary
./result/bin/percy --version
```

**Using Bun Compile Directly**

The binary packaging logic is available as `scripts/percy-make-binary.sh` for reuse in CI or non-Nix release jobs:

```bash
./scripts/percy-make-binary.sh <output-path>
```

This script:
- Compiles the CLI using `bun build --compile`
- Handles output path normalization
- Sets executable permissions

Note: Bun compile builds for the current platform. For cross-platform builds, run the script on each target platform or use Bun's cross-compilation features if available.

### Lockfile Updates

When dependencies change, `bun.lockb` should be updated:

```bash
bun install
```

The lockfile is used by Bun during the Nix build. For reproducible builds, commit `bun.lockb` to version control.

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

## Flake Check Usage

The flake defines packages for multiple systems (x86_64-linux, aarch64-linux, x86_64-darwin, aarch64-darwin), but local development machines typically can only build for their native system.

### Local Development

On your local machine (e.g., an aarch64-darwin Mac), use:

```bash
# Check only the current system (recommended)
nix flake check

# Or explicitly specify the system
nix flake check --system aarch64-darwin
```

This will:
- Only check packages for systems that can be built locally (darwin systems on macOS)
- Skip Linux packages that require remote builders or cross-compilation
- Avoid errors about "required system not available"

The flake defines conditional checks that only run for darwin systems when on macOS, allowing local checks to succeed while keeping multi-system package definitions for CI.

### Why `--all-systems` Fails Locally

Running `nix flake check --all-systems` on a macOS machine will fail because:

1. It attempts to build Linux packages (x86_64-linux, aarch64-linux) that cannot be built on macOS without:
   - Remote Linux builders configured in `nix.conf`
   - Cross-compilation setup
   - A Linux VM or container

2. The error messages will show:
   ```
   Required system: 'x86_64-linux'
   Current system: 'aarch64-darwin'
   Reason: required system or feature not available
   ```

This is expected behavior - your local machine simply cannot build those systems.

### CI Usage

In CI environments (like GitHub Actions) that have proper builders for all target systems, you can use:

```bash
nix flake check --all-systems
```

The CI workflow (`.github/workflows/nix/executable.yml`) builds each system separately on appropriate runners, which is the correct approach for multi-system builds.

