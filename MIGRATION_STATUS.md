# Percy CLI Toolchain Migration

## Status

**Migration: Complete ✅**

The Percy CLI has been migrated from the legacy stack (Yarn + Lerna + Babel + Rollup + Karma) to a modern toolchain centered on Bun, Vitest, and bun2nix.

- **Package Manager**: Bun (with native workspaces)
- **Build**: Bun bundler only (no Babel, no Rollup)
- **Tests**:
  - Node tests: Bun test runner
  - Browser-style tests: Vitest + jsdom
- **Nix**: bun2nix-backed offline, reproducible builds
- **Lockfiles**: bun.lockb + bun.nix (both committed)

## Architecture: Before vs After

### Legacy
- Package manager: Yarn (workspaces)
- Monorepo tool: Lerna 6
- Build: Babel + Rollup
- Tests: Jasmine + Karma
- Coverage: nyc
- Nix: dream2nix / mkYarnPackage
- Lockfile: yarn.lock

### Current
- Package manager: Bun
- Monorepo: Bun workspaces (workspaces in package.json)
- Build: bun build (ESM + browser bundles)
- Tests:
  - Node: bun test
  - Browser: Vitest (jsdom environment)
- Coverage:
  - Node: Bun test coverage
  - Browser: Vitest @vitest/coverage-v8
- Nix: bun2nix.fetchBunDeps + bun2nix.hook
- Lockfiles: bun.lockb + generated bun.nix

## Completed Phases

### 1. Bun Migration
- Replaced all lerna run and yarn invocations with bun run --filter and bun install.
- Removed lerna.json and lerna devDependency.
- Added bunfig.toml and updated CI (GitHub Actions) to:
  - Install Bun (oven-sh/setup-bun@v1)
  - Use bun install instead of yarn
  - Use bun run build and bun run --filter in workflows.
- Switched cache keys from yarn.lock to bun.lockb.

### 2. Build System (Babel/Rollup → Bun)
- Replaced Babel + Rollup build logic with bun build:
  - Node builds: bun build → ESM output (native module format).
  - Browser bundles: bun build → iife format where needed.
- Removed:
  - All Babel deps (@babel/*, babel plugins) and babel.config.*.
  - All Rollup deps (core + plugins) and rollup.config.js.
- Updated build scripts (scripts/build.js, etc.) to use Bun.
- Binary packaging: Migrated from `pkg` to Nix-wrapped Node CLI (canonical approach)
  - Simple shell wrapper that runs Node on the ESM entrypoint
  - Works directly with ESM builds from `bun run build`
  - Removed experimental `build:binary` script (Bun --compile path) from root package.json

### 3. Nix Integration (bun2nix)
- Integrated bun2nix from nix-community:
  - bun.nix (generated from bun.lockb) committed to the repo.
  - bun2nix.fetchBunDeps used to fetch dependencies offline.
  - bun2nix.hook wired into builds so bun install is offline.
- Introduced layered Nix packages:
  1. src-patched: removes "type": "module" where needed for CJS compatibility.
  2. node-tree: runs bun install --frozen-lockfile and bun run build (ESM output).
  3. percy-cli: Nix-wrapped Node CLI (simple shell wrapper for ESM entrypoint).
- Removed pkg-based binary packaging in favor of Nix-wrapped Node CLI:
  - Works directly with ESM builds from `bun run build`
  - No separate binary compilation step needed
  - Removed experimental `build:binary` script from root package.json
- Added Nix apps:
  - nix run .#bun-install → generate bun.lockb
  - nix run .#bun2nix-generate → generate bun.nix
  - nix run .#update-lockfiles → run both.

### 4. Test Migration (Jasmine/Karma → Bun + Vitest)
- Node tests:
  - Migrated from Jasmine to Bun's test runner.
  - Removed Jasmine deps and Jasmine-specific config.
- Browser tests:
  - Migrated from Karma + Rollup to Vitest + jsdom.
  - Added vitest, @vitest/coverage-v8, and jsdom.
  - Created vitest.config.mts with jsdom environment.
  - Updated test helpers and scripts to use Vitest APIs.
  - Removed Karma config (karma.config.*) and deps.
- Coverage:
  - Browser: vitest run --coverage (v8 provider).
  - Node: bun test --coverage.
- nyc removed.

### 5. Final Cleanup
- Removed:
  - Karma, Rollup, Babel, Jasmine, nyc, cross-env, @nx/nx-darwin-arm64, @vitest/ui, gaze.
- Updated ESLint config:
  - Dropped jasmine environment references.
  - Dropped @babel/eslint-parser and eslint-plugin-babel in favor of ESLint's native parser.
- Updated docs and CI workflows to match the new test + build story.
- Standardized binary approach:
  - Removed `build:binary` script from root package.json (Bun --compile experimental path)
  - Canonical binary is now Nix-wrapped Node CLI only

## Current devDependencies (Root)

At the root, the devDependencies are intentionally minimal:

**Linting**
- eslint
- eslint-config-standard
- eslint-plugin-import
- eslint-plugin-node
- eslint-plugin-promise

**Testing**
- vitest (browser tests)
- @vitest/coverage-v8 (coverage for Vitest)
- jsdom (browser-like environment)

**Test utilities**
- memfs (in-memory filesystem for tests)
- tsd (TypeScript definition tests)

**Total**: 10 development dependencies (down from 20+ in the legacy stack)

## How to Use

### Local

```bash
# Install deps
bun install

# Build
bun run build

# Run Node tests
bun test

# Run browser tests
bunx vitest run

# Coverage
bun test --coverage              # Node
bunx vitest run --coverage       # Browser
```

### Nix

```bash
# Build CLI binary
nix build .#percy-cli

# Run full check pipeline (layers + binary smoke tests)
nix flake check

# Verification commands (after committing changes)
nix run .#bun-install      # Install dependencies, generate bun.lockb
nix run .#build            # Build all packages
nix run .#test             # Run all tests (Node + Browser)
nix run .#test-browser      # Run browser tests only (Vitest)
nix run .#test-coverage    # Run tests with coverage
nix run .#lint             # Lint all packages
```

### Lockfile Updates

**Important**: Both `bun.lockb` and `bun.nix` must exist and be committed for reproducible Nix builds.

```bash
# Recommended: update both lockfiles via Nix app (requires clean git state)
nix run .#update-lockfiles

# Or manually (if Bun is installed):
bun install                    # Generates bun.lockb
bunx bun2nix -o bun.nix       # Generates bun.nix from bun.lockb
git add bun.lockb bun.nix
```

**Note**: If `bun.lockb` is missing, `nix build` will fail because Bun needs the lockfile to resolve dependencies offline. Generate it first using one of the methods above.

## Nix Build System

The build uses Bun to manage Node.js dependencies and build the Percy CLI monorepo. The Nix integration uses `bun2nix` (from nix-community) to provide offline, reproducible builds.

### Architecture

The build follows a multi-layer architecture:

1. **Layer 1: Patched Source** (`nix/src-patched.nix`)
   - Removes `"type": "module"` declarations from package.json files
   - Ensures consistent CommonJS semantics throughout the build

2. **Layer 2: Node Tree** (`default.nix` - nodeTree)
   - Uses `bun2nix` to fetch dependencies offline from `bun.nix`
   - Uses Bun to install dependencies from `bun.lockb` using offline cache
   - Includes all devDependencies
   - Runs `bun run build` to compile all packages as ESM using Bun's workspace support

3. **Layer 3: CLI Binary Packaging** (`default.nix`)
   - **`percy-cli`**: Nix-wrapped Node CLI - simple shell script that runs Node on the ESM entrypoint
   - Works directly with ESM builds from `bun run build` (no separate binary compilation)
   - Supports: x86_64-linux, aarch64-linux, x86_64-darwin, aarch64-darwin
   - The root `build:binary` script (Bun --compile experimental path) has been removed

### How bun2nix Works

1. **bun.nix**: Pre-generated file (committed to version control) that contains all dependency fetch URLs and hashes
2. **bun2nix.fetchBunDeps**: Fetches all dependencies offline using the information in `bun.nix`
3. **bun2nix.hook**: Sets up Bun to use the offline cache during `bun install`
4. **Bun install**: Installs dependencies from the offline cache (no network access needed)
5. **Bun build**: Builds all packages using Bun's native workspace support

This provides:
- **Offline builds**: No network access required during Nix builds
- **Reproducibility**: All dependencies are pinned with hashes
- **Speed**: Bun's fast installs combined with Nix's binary cache

### Building

**Prerequisites**: `bun.lockb` and `bun.nix` must exist. If missing, run `nix run .#update-lockfiles` first (requires clean git state).

```bash
# Build the binary for your system
nix build

# Build for a specific system
nix build .#percy-cli

# Build all layers
nix build .#src-patched
nix build .#node-tree
nix build .#prepared-cli
nix build .#percy-cli
```

### Running Checks

```bash
# Run all checks (builds all layers and verifies binary)
nix flake check
```

This will:
- Build all layers (src-patched, node-tree, prepared-cli, percy-cli)
- Verify the binary exists and is executable
- Run a smoke test (--version or --help)

### Updating Dependencies

When dependencies change, use Nix apps to generate the required lockfiles:

```bash
# Update both lockfiles at once (recommended)
nix run .#update-lockfiles

# Or update them separately:
nix run .#bun-install          # Generate bun.lockb
nix run .#bun2nix-generate     # Generate bun.nix from bun.lockb
```

Alternatively, use Bun directly:

```bash
bun install                    # Update bun.lockb
bunx bun2nix -o bun.nix        # Regenerate bun.nix
```

**Important**: Both `bun.lockb` and `bun.nix` must be committed to version control for reproducible Nix builds.

## Alternatives Considered

During the migration from Karma to modern browser testing, several options were evaluated:

**Playwright** (originally recommended): Excellent browser automation but requires significant test rewrites and is heavier than needed.

**Vitest + jsdom** (chosen): Jest-compatible API for easier migration from Jasmine, better Bun integration, Vite replaces Rollup entirely, faster execution without browser startup, and native ESM support. The split architecture uses Bun test for Node tests and Vitest for browser tests, each optimized for its environment.

**Web Test Runner**: Lightweight alternative but smaller community.

**Puppeteer + Jest/Vitest**: Mature but requires manual browser management and only supports Chromium.

Vitest was chosen primarily for its Jest-compatible API (minimal test changes), seamless Bun integration, and ability to completely remove Rollup (Vite provides Rollup capabilities internally).

## Migration Benefits

1. ✅ **Faster installs**: Bun installs 10-100x faster than Yarn
2. ✅ **Faster builds**: Bun bundler is very fast
3. ✅ **Simpler toolchain**: Reduced from Lerna + Yarn + Babel + Rollup + Karma + Jasmine + nyc to Bun + Vitest (10 devDependencies vs 20+)
4. ✅ **Better DX**: Faster feedback loops
5. ✅ **Native TypeScript**: No need for separate TS compilation
6. ✅ **Offline Nix builds**: bun2nix provides reproducible, offline builds
7. ✅ **Complete Rollup removal**: No more Rollup dependencies (Vite replaces it)
8. ✅ **Simpler test architecture**: No pre-bundling step needed
9. ✅ **Better browser testing**: Vitest + jsdom provides faster, simpler testing
10. ✅ **Native ESM support**: No more bundling step for browser tests
11. ✅ **Modern tooling**: Fully modernized toolchain

## Related Documentation

- [Bun Documentation](https://bun.sh/docs)
- [bun2nix Documentation](https://github.com/nix-community/bun2nix)
- [Vitest Documentation](https://vitest.dev/)
- [jsdom Documentation](https://github.com/jsdom/jsdom)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
- [Percy CLI Development Guide](./packages/cli/README.md)
