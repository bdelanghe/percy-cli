# Percy CLI Toolchain Migration

## Status

**Migration: Complete ✅**

The Percy CLI has been migrated from the legacy stack (Yarn + Lerna + Babel + Rollup + Karma) to a modern toolchain centered on Bun, Vitest, and bun2nix.

- **Package Manager**: Bun (with native workspaces)
- **Build**: Bun bundler only (no Babel, no Rollup)
- **Tests**:
  - Node tests: Bun test runner
  - Browser-style tests: Vitest + jsdom
- **Linting**: ESLint 9 with flat config format
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
- Linting: ESLint 9 (flat config format)
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

### 6. Dev Dependencies Modernization (ESLint 9 Upgrade + Aggressive Simplification)
- **ESLint 7.x → 9.x**: Aggressive upgrade to latest ESLint with flat config migration
  - Migrated from `.eslintrc` YAML format to `eslint.config.js` flat config format
  - Removed all 17 test directory `.eslintrc` files (consolidated into root flat config)
  - Replaced `eslint-plugin-node` with `eslint-plugin-n` (ESLint 9 compatible)
  - Added `globals` package for ESLint 9 flat config support
- **ESLint simplification (brutalist approach)**:
  - **Removed**: `eslint-config-standard`, `eslint-plugin-n`, `eslint-plugin-promise` (unused or only used to disable rules)
  - **Kept**: `eslint-plugin-import` (only plugin actually used - `import/no-extraneous-dependencies`)
  - **Replaced**: StandardJS config with ESLint's built-in `@eslint/js` recommended config + minimal custom rules
  - Result: Minimal ESLint setup with only essential rules
- **Test stack updated**:
  - `vitest`: `^2.0.0` → `^2.1.0`
  - `@vitest/coverage-v8`: `^2.0.0` → `^2.1.0`
  - `jsdom`: `^24.0.0` → `^25.0.0` (used in vitest.config.mts)
  - `tsd`: `^0.31.2` → `^0.32.0` (used for .test-d.ts files)
- **Utilities updated**:
  - `memfs`: `^3.4.0` → `^3.5.0` (used in packages/config/test/helpers.js)

## Current devDependencies (Root)

At the root, the devDependencies are intentionally minimal (aggressive simplification):

**Linting** (minimal setup)
- @eslint/js ^9.0.0 (ESLint's built-in recommended config)
- eslint ^9.0.0 (flat config format)
- eslint-plugin-import ^2.31.0 (only plugin used - for `import/no-extraneous-dependencies`)
- globals ^15.0.0 (required for ESLint 9 flat config)

**Testing**
- vitest ^2.1.0 (browser tests)
- @vitest/coverage-v8 ^2.1.0 (coverage for Vitest)
- jsdom ^25.0.0 (browser-like environment, used in vitest.config.mts)

**Test utilities**
- memfs ^3.5.0 (in-memory filesystem for tests, used in packages/config/test/helpers.js)
- tsd ^0.32.0 (TypeScript definition tests, used for .test-d.ts files)

**Total**: 9 development dependencies (down from 20+ in the legacy stack, down from 11 after ESLint 9 upgrade)

**Note**: ESLint 9 uses the new "flat config" format (`eslint.config.js`) instead of the legacy `.eslintrc` format. All test directory `.eslintrc` files have been consolidated into the root flat config with file pattern overrides. The ESLint setup uses a "brutalist" minimal approach: ESLint's built-in recommended config + only the `import/no-extraneous-dependencies` rule from eslint-plugin-import. StandardJS config and unused plugins (eslint-plugin-n, eslint-plugin-promise) were removed.

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

### Troubleshooting

#### Bun not found
If you see "bun not found" errors:
- Ensure Bun is available in nixpkgs for your system
- Check that `nativeBuildInputs` includes `bun` in `flake.nix`
- Verify Bun is installed in the dev shell: `nix develop`

#### Lockfile issues
If `bun.lockb` doesn't exist:
- Bun will generate it automatically during `bun install`
- For reproducible builds, commit `bun.lockb` to version control
- Use `bun install --frozen-lockfile` in CI/Nix builds

If `bun.nix` doesn't exist or is outdated:
- Regenerate it using Nix: `nix run .#bun2nix-generate`
- Or manually: `bunx bun2nix -o bun.nix`
- Commit the updated `bun.nix` file
- The build will fail if `bun.nix` is missing or doesn't match `bun.lockb`

#### Build failures
- Check the build logs: `nix log /nix/store/...`
- Verify all source files are present
- Ensure `bun.lockb` is up to date (or let Bun generate it)
- Check that workspace packages are correctly configured

#### Native module issues
If you encounter native module issues:
- Verify the native module is compatible with Bun
- Check that platform-specific packages (e.g., `@nx/nx-darwin-arm64`) are included
- Ensure Bun is using the correct Node.js version for compatibility

### Building x86_64-darwin on Apple Silicon

If you're on an Apple Silicon (aarch64-darwin) Mac and want to build x86_64-darwin (Intel) binaries locally, you can use Rosetta 2 emulation.

#### Setup

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

#### How It Works

- Nix will use your aarch64 host to run x86_64 tools under Rosetta 2
- The build will produce a store path for x86_64-darwin (Intel binary)
- This allows you to build Intel macOS binaries locally without needing a separate Intel Mac

#### Alternative: Remote Builder

If you have an Intel Mac (or CI runner) available, you can configure it as a remote Nix builder for faster, native x86_64-darwin builds:

```conf
builders = ssh://builder@intel-mac x86_64-darwin - 4 1 big-parallel,kvm
```

Then use the same build commands - Nix will automatically offload to the remote builder.

### Flake Check Usage

The flake defines packages for multiple systems (x86_64-linux, aarch64-linux, x86_64-darwin, aarch64-darwin), but local development machines typically can only build for their native system.

#### Local Development

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

#### Why `--all-systems` Fails Locally

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

#### CI Usage

In CI environments (like GitHub Actions) that have proper builders for all target systems, you can use:

```bash
nix flake check --all-systems
```

The CI workflow (`.github/workflows/nix/executable.yml`) builds each system separately on appropriate runners, which is the correct approach for multi-system builds.

### Nix Build System Files

- `flake.nix` - Main flake configuration with bun2nix integration
- `default.nix` - Main package definition using bun2nix
- `bun.nix` - Pre-generated dependency cache (committed to version control)
- `bun.lockb` - Bun's binary lockfile (committed to version control)
- `nix/src-patched.nix` - Source patching layer
- `nix/prepared-cli.nix` - CLI preparation layer
- `nix/pkg-wrapper.nix` - pkg binary wrapper
- `nix/percy-config.nix` - Build configuration (versions, targets)
- `nix/dev-shell.nix` - Development shell with Bun

## Historical Reference: Karma Migration

This section documents the original migration plan from Karma to modern browser testing. The migration was completed using **Vitest + jsdom** instead of the originally recommended Playwright.

### Original Problem

The project was using Karma 6.0.2 with Rollup for browser-based testing. This setup had several limitations:
- Complex configuration with multiple files (`karma.config.cjs` + `rollup.config.js`)
- Slower test execution (browser startup overhead)
- Rollup dependency only used for tests
- Less modern tooling integration

### Alternatives Considered

#### Option 1: Playwright Test (Originally Recommended)
**Pros:**
- Modern, actively maintained by Microsoft
- Excellent browser automation and testing
- Built-in test runner
- Great debugging tools (UI mode, trace viewer)
- Supports multiple browsers (Chromium, Firefox, WebKit)

**Cons:**
- Different API from Jasmine (would need test migration)
- Requires learning new APIs
- Heavier than some alternatives

**Migration Complexity:** Medium-High (test rewrite needed)

#### Option 2: Vitest with Browser Mode (Chosen)
**Pros:**
- Jest-compatible API (familiar if using Jest)
- Built-in browser mode support (uses Vite internally)
- Fast and modern
- Great TypeScript support
- Can use same test files for Node and browser
- Built-in coverage
- Good Bun integration potential
- **Vite replaces Rollup**: Vite is the engine, providing Rollup capabilities without direct Rollup dependency

**Cons:**
- Browser mode is relatively new (less mature than Playwright)
- May have compatibility issues with some browser APIs
- Less mature than Playwright for browser testing

**Migration Complexity:** Medium (test rewrite needed, but similar to Jest)

**Note:** Vitest was chosen because it provides Jest-compatible API (easier migration from Jasmine), better Bun integration, and Vite replaces Rollup entirely.

#### Option 3: Web Test Runner (@web/test-runner)
**Pros:**
- Modern, lightweight alternative to Karma
- Minimal configuration
- Uses native ES modules (no bundling needed)
- Supports multiple browsers

**Cons:**
- Smaller community than Playwright
- Less feature-rich than Playwright

**Migration Complexity:** Low-Medium (minimal test changes)

#### Option 4: Puppeteer + Jest/Vitest
**Pros:**
- Puppeteer is mature and well-documented
- Can use Jest/Vitest for test framework

**Cons:**
- Requires manual browser management
- More setup complexity
- Puppeteer only supports Chromium (not Firefox)

**Migration Complexity:** Medium-High

### Why Vitest Was Chosen

Despite the original recommendation for Playwright, **Vitest + jsdom** was chosen because:

1. **Easier migration**: Jest-compatible API means existing Jasmine tests require minimal changes
2. **Better Bun integration**: Vitest works seamlessly with Bun
3. **Vite replaces Rollup**: Complete Rollup removal possible (Vite uses Rollup internally)
4. **Faster execution**: jsdom doesn't require browser startup
5. **Native ESM support**: No pre-bundling step needed
6. **Unified test runner**: Can use Vitest for both Node and browser tests

### Vite Replaces Rollup for Browser Tests

**Key Insight**: Vite can replace Rollup for almost everything Rollup is used for in Karma today.

#### How Vite Replaces Rollup

1. **Vite uses Rollup internally**: Vite's production build pipeline is Rollup with a configuration layer
2. **For browser tests, Vite simplifies everything**:
   - Modern test runners (Playwright, Vitest) understand ES modules natively
   - No more pre-bundling step required
   - No more `karma-rollup-preprocessor`
   - Vite becomes the dev server + transformer if needed

3. **With Vitest Browser Mode**:
   - Vite is the engine (Vitest is built on Vite like Jest is built on its transformer)
   - Full Vite capabilities available

#### What This Means

- ✅ **Complete Rollup removal possible**: After Karma migration, Rollup can be fully removed
- ✅ **Simpler architecture**: No more separate bundling step for tests
- ✅ **Better performance**: Native ESM support means faster test execution
- ✅ **Modern tooling**: Vite provides Rollup's capabilities with better DX

### Implementation Approach

The migration was completed using Vitest with jsdom environment:

1. **Installed Vitest + jsdom**: Added vitest, @vitest/ui, @vitest/coverage-v8, jsdom
2. **Created Vitest configuration**: `vitest.config.mts` with jsdom environment
3. **Updated test helpers**: Adapted for Vitest (removed Karma-specific code)
4. **Updated test infrastructure**: Modified `scripts/test.js` to use Vitest
5. **Removed Karma**: Deleted all Karma dependencies and `karma.config.cjs`
6. **Removed Rollup**: Deleted `rollup.config.js` and rollup config from package.json files

### Challenges and Solutions

#### 1. Test Framework Migration
- **Challenge**: Converting Jasmine tests to Vitest syntax
- **Solution**: Vitest's Jest-compatible API made migration straightforward
- **Impact**: Low - minimal test file updates needed

#### 2. Coverage Collection
- **Challenge**: Karma uses istanbul-lib-coverage, need equivalent
- **Solution**: Use Vitest's built-in v8 coverage provider
- **Impact**: Low - well-supported in Vitest

#### 3. Test Helpers
- **Challenge**: Browser test helpers may need updates
- **Solution**: Migrated helpers to use Vitest's expect API
- **Impact**: Low - helper functions updated easily

#### 4. Browser Compatibility
- **Challenge**: jsdom doesn't distinguish between browsers
- **Solution**: Most tests work with jsdom; browser-specific tests can be handled separately if needed
- **Impact**: Low - jsdom covers most browser testing needs

## Migration Benefits

1. ✅ **Faster installs**: Bun installs 10-100x faster than Yarn
2. ✅ **Faster builds**: Bun bundler is very fast
3. ✅ **Simpler toolchain**: Reduced from Lerna + Yarn + Babel + Rollup + Karma + Jasmine + nyc to Bun + Vitest (9 devDependencies vs 20+)
4. ✅ **Better DX**: Faster feedback loops
5. ✅ **Native TypeScript**: No need for separate TS compilation
6. ✅ **Offline Nix builds**: bun2nix provides reproducible, offline builds
7. ✅ **Complete Rollup removal**: No more Rollup dependencies (Vite replaces it)
8. ✅ **Simpler test architecture**: No pre-bundling step needed
9. ✅ **Better browser testing**: Vitest + jsdom provides faster, simpler testing
10. ✅ **Native ESM support**: No more bundling step for browser tests
11. ✅ **Modern tooling**: Fully modernized toolchain
12. ✅ **ESLint 9 flat config**: Modern configuration format, better performance, consolidated configs
13. ✅ **Up-to-date dev dependencies**: All dev tools on latest stable versions
14. ✅ **Brutalist ESLint setup**: Minimal config using only ESLint core + one essential plugin (import/no-extraneous-dependencies)

## Related Documentation

- [Bun Documentation](https://bun.sh/docs)
- [bun2nix Documentation](https://github.com/nix-community/bun2nix)
- [Vitest Documentation](https://vitest.dev/)
- [jsdom Documentation](https://github.com/jsdom/jsdom)
- [ESLint 9 Migration Guide](https://eslint.org/docs/latest/use/migrate-to-9.0.0)
- [ESLint Flat Config](https://eslint.org/docs/latest/use/configure/configuration-files-new)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
- [Percy CLI Development Guide](./packages/cli/README.md)
