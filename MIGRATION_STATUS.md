# Percy CLI Migration Status

## Overview

This document tracks the complete migration from the legacy toolchain (Lerna + Yarn + Babel + Rollup + Karma) to modern tooling (Bun + bun2nix + Vitest). This multi-phase migration improves build performance, simplifies the toolchain, and modernizes the development experience.

## Migration Journey

### Original Architecture (Before Migration)
- **Package Manager**: Yarn (with workspaces)
- **Monorepo Tool**: Lerna 6.0.1
- **Build Tools**: Babel, Rollup
- **Test Runner**: Jasmine, Karma
- **Nix Integration**: dream2nix (nodejs-package-json-v3) + mkYarnPackage
- **Lock File**: yarn.lock

### Current Architecture (Migration Complete) ✅
- **Package Manager**: Bun ✅
- **Monorepo Tool**: Bun workspaces (native) ✅
- **Build Tools**: Bun bundler only ✅ (Babel and Rollup completely removed)
- **Test Runner**: Bun test runner (Node tests) ✅, Vitest + jsdom (browser tests) ✅
- **Nix Integration**: bun2nix from nix-community ✅
- **Lock File**: bun.lockb ✅

### Target Architecture
The migration is complete. The current architecture matches the target:
- **Package Manager**: Bun
- **Monorepo Tool**: Bun workspaces (native)
- **Build Tools**: Bun bundler only (Babel and Rollup completely removed)
- **Test Runner**: Bun test runner (Node tests), Vitest + jsdom (browser tests)
- **Nix Integration**: bun2nix (offline, reproducible builds)
- **Lock File**: bun.lockb

## Completed Work

### Phase 1: Bun Package Manager Migration ✅

#### Core Configuration
- ✅ **package.json**: Replaced all `lerna run` commands with `bun run --filter`
- ✅ **Removed lerna.json**: Deleted (Bun workspaces handle this natively)
- ✅ **Created bunfig.toml**: Added Bun configuration file
- ✅ **Removed Lerna dependency**: Removed `lerna` from devDependencies

#### Scripts
- ✅ **package.json scripts**: Updated to use `bun run --filter` for workspace commands
- ✅ **scripts/executable.sh**: Updated `yarn install` → `bun install`, `yarn build` → `bun run build`

#### CI/CD
- ✅ **.github/workflows/test.yml**: Updated to use Bun instead of Yarn
  - Added `oven-sh/setup-bun@v1` action
  - Replaced `yarn` with `bun install`
  - Replaced `yarn build` with `bun run build`
  - Replaced `yarn workspace` with `bun run --filter`
  - Updated cache keys from `yarn.lock` to `bun.lockb`

### Phase 2: Build System Migration ✅

#### Babel Removal
- ✅ **scripts/build.js**: Replaced Babel and Rollup with Bun's bundler
  - Node.js builds now use `bun build` with `--format cjs` for CommonJS output
  - Browser bundles now use `bun build` with `--format iife` for IIFE format
  - Preserves directory structure for Node.js builds
  - Handles browser bundle configuration from package.json `rollup` field
- ✅ **Dependencies Removed**: 
  - `@babel/cli`, `@babel/core`, `@babel/preset-env`, `@babel/register`
  - `babel-plugin-istanbul`, `babel-plugin-module-resolver`, `babel-plugin-transform-import-meta`
- ✅ **Configuration Files**:
  - `babel.config.cjs`: Deleted (no longer used)
  - `.eslintrc`: Updated with note about potential future parser change
- ✅ **Test Scripts**:
  - `scripts/loader.js`: Removed Babel usage, now uses Bun's native module handling
  - `scripts/test.js`: Removed babel-register.cjs reference, updated for Bun
  - `scripts/babel-register.cjs`: Deleted (no longer needed)
- ✅ **ESLint Parser**: `@babel/eslint-parser` and `eslint-plugin-babel` removed, using ESLint's native parser

#### Rollup Removal
- ✅ **Build System**: Rollup removed from build system, replaced with Bun bundler
- ✅ **Dependencies Removed**: `rollup` and all `@rollup/plugin-*` packages from build system
- ✅ **Vitest replaces Karma**: Vitest + jsdom now used for browser tests
- ✅ **Vite replaces Rollup**: Vite (used by Vitest) handles bundling, Rollup completely removed

### Phase 3: Nix Integration Migration ✅

#### bun2nix Integration
- ✅ **flake.nix**: Migrated to bun2nix from nix-community (replaces custom Bun integration)
- ✅ **default.nix**: Updated to use `bun2nix.fetchBunDeps` and `bun2nix.hook` for offline builds
- ✅ **bun.nix**: Generated and committed (contains offline dependency cache)
- ✅ **dev-shell.nix**: Replaced `yarn` with `bun` in buildInputs
- ✅ **nix/src-patched.nix**: Removed bun.nix generation from postinstall (should be committed)
- ✅ **nix/percy-firefox.nix**: Updated to use `bun` instead of `yarn`
- ✅ **nix/offline-cache.nix**: Deleted (replaced by bun2nix)

#### Nix Apps for Lockfile Management
- ✅ **flake.nix apps**: Added Nix apps for generating lockfiles
  - `nix run .#bun-install` - Generate bun.lockb
  - `nix run .#bun2nix-generate` - Generate bun.nix from bun.lockb
  - `nix run .#update-lockfiles` - Update both lockfiles at once

### Phase 4: Test Infrastructure Updates ✅

#### Node.js Tests
- ✅ **package.json test scripts**: Updated to use `bun test` and `bun test --coverage`
- ✅ **Bun test runner**: Now used for Node.js tests (replaces Jasmine for Node tests)
- ✅ **Jasmine removed**: All Jasmine dependencies removed, tests migrated to use Vitest/Bun APIs
- ✅ **Test helpers updated**: All test helper files migrated from Jasmine to Vitest APIs

### Phase 5: Browser Testing Migration (Karma → Vitest) ✅

**Status**: ✅ Complete

**Goal**: Replace Karma + Rollup with Vitest + jsdom for browser testing, enabling complete Rollup removal.

**What Was Done**:
1. ✅ **Installed Vitest + jsdom**: Added vitest, @vitest/coverage-v8, jsdom
2. ✅ **Created Vitest configuration**: `vitest.config.mts` with jsdom environment
3. ✅ **Updated test helpers**: Adapted for Vitest (removed Karma-specific code)
4. ✅ **Updated test infrastructure**: Modified `scripts/test.js` to use Vitest for browser tests and Bun for node tests
5. ✅ **Removed Karma**: Deleted all Karma dependencies and `karma.config.cjs`
6. ✅ **Removed Rollup**: Deleted `rollup.config.js` and rollup config from package.json files
7. ✅ **Removed nyc**: Replaced with Vitest's built-in coverage for browser tests and Bun's coverage for node tests

**Why Vitest?**
- Modern, actively maintained
- Jest-compatible API (easy migration from Jasmine)
- Vite replaces Rollup (simpler architecture)
- Good Bun integration
- Built-in coverage support
- Faster execution (no browser startup)
- Native ESM support

**Benefits Achieved**:
- ✅ Complete Rollup removal
- ✅ Simpler architecture (no pre-bundling step)
- ✅ Better performance (no browser startup)
- ✅ Modern tooling
- ✅ Native ESM support
- ✅ Unified test runner (can use Vitest for both Node and browser tests)

### Phase 6: Final Cleanup ✅

**Status**: ✅ Complete

**Tasks Completed**:
- ✅ Removed all Karma dependencies
- ✅ Removed all Rollup dependencies (for tests)
- ✅ Removed `rollup.config.js`
- ✅ Removed `karma.config.cjs`
- ✅ Removed `@babel/eslint-parser` and `eslint-plugin-babel` (replaced with ESLint's native parser)
- ✅ Removed Jasmine and jasmine-spec-reporter (replaced with Bun test runner + Vitest APIs)
- ✅ Removed `nyc` (replaced with Vitest/Bun built-in coverage)
- ✅ Removed `cross-env` (not needed on macOS/Nix/Bun)
- ✅ Removed `@nx/nx-darwin-arm64` (no Nx usage)
- ✅ Removed `@vitest/ui` (not used)
- ✅ Updated test scripts to use Vitest coverage for browser tests and Bun coverage for node tests
- ✅ Updated ESLint configs to remove jasmine environment references
- ✅ Updated documentation
- ⏳ Final testing and validation (pending actual test runs)

## Current State

### What's Working
- ✅ Bun package management and workspace commands
- ✅ Bun bundler for Node.js and browser builds
- ✅ Bun test runner for Node.js tests (Jasmine completely removed)
- ✅ Vitest + jsdom for browser tests
- ✅ bun2nix for offline, reproducible Nix builds
- ✅ All build scripts migrated to Bun
- ✅ ESLint using native parser (Babel ESLint parser removed)
- ✅ Minimal dependency footprint (only actively used packages remain)

### Final DevDependencies

The migration resulted in a minimal, focused set of development dependencies:

**ESLint Stack** (5 packages) - For code linting:
- `eslint`
- `eslint-config-standard`
- `eslint-plugin-import`
- `eslint-plugin-node`
- `eslint-plugin-promise`

**Testing Stack** (3 packages) - For test execution and coverage:
- `vitest` - Core test runner for browser tests
- `@vitest/coverage-v8` - Coverage collection for Vitest
- `jsdom` - Browser-like environment for browser tests

**Test Utilities** (3 packages) - For test infrastructure:
- `gaze` - File watching for test watch mode
- `memfs` - In-memory filesystem for test mocking
- `tsd` - TypeScript definition testing

**Total**: 11 development dependencies (down from 20+ in the legacy stack)

All legacy dependencies (Karma, Rollup, Babel, Jasmine, nyc, cross-env, @nx/nx-darwin-arm64, @vitest/ui) have been removed.


## Remaining Work

### Verification Steps

1. **Install dependencies via Nix/bun2nix**
   - The minimal dependency set (ESLint stack, Vitest, jsdom, test utilities) is in `package.json`
   - Run `bun install` or use Nix to install dependencies
   - Regenerate `bun.nix` if using bun2nix: `nix run .#bun2nix-generate`

2. **Run tests to verify everything works**
   - Run browser tests: `bun test:browser` or `vitest run`
   - Run all tests: `bun test` (Node tests) + `bun test:browser` (browser tests)
   - Run with coverage: 
     - Browser tests: `vitest run --coverage`
     - Node tests: `bun test --coverage`

3. **Fix any test failures**
   - All Jasmine APIs have been migrated to Vitest/Bun equivalents
   - Common migrations completed:
     - `expectAsync().toBeResolvedTo()` → `await expect(...).resolves.toBe(...)`
     - `jasmine.createSpy()` → `vi.fn()`
     - `jasmine.clock()` → `vi.useFakeTimers()`
     - `spyOn()` → `vi.spyOn()`
     - `jasmine.any()` → `expect.any()`
     - All Jasmine matchers → Vitest equivalents
   - Some test files may still need updates if tests fail

4. **Update CI/CD if needed**
   - Update GitHub Actions workflows to use Vitest instead of Karma
   - Remove any Karma-specific setup steps
   - Ensure Vitest and jsdom are available in CI environment
   - Update test commands to use `vitest run` for browser tests

## Nix Build System

This section covers the Nix build system for building the Percy CLI binary using Bun.

### Overview

The build uses Bun to manage Node.js dependencies and build the Percy CLI monorepo. The Nix integration uses `bun2nix` (from nix-community) to provide offline, reproducible builds. Bun reads `bun.lockb` and installs dependencies from a pre-fetched offline cache, providing fast, reproducible builds with native workspace support.

### Architecture

The build follows a multi-layer architecture:

1. **Layer 1: Patched Source** (`nix/src-patched.nix`)
   - Removes `"type": "module"` declarations from package.json files
   - Ensures consistent CommonJS semantics throughout the build

2. **Layer 2: Node Tree** (`default.nix` - nodeTree)
   - Uses `bun2nix` to fetch dependencies offline from `bun.nix`
   - Uses Bun to install dependencies from `bun.lockb` using offline cache
   - Includes all devDependencies
   - Runs `bun run build_cjs` to compile all packages using Bun's workspace support

3. **Layer 3: Prepared CLI** (`nix/prepared-cli.nix`)
   - Applies CLI-specific patches for pkg packaging
   - Patches `percy.js` imports and `NODE_ENV`

4. **Layer 4: Binary** (`nix/pkg-wrapper.nix`)
   - Uses `pkg` to create platform-specific binaries
   - Supports: x86_64-linux, aarch64-linux, x86_64-darwin, aarch64-darwin

### How bun2nix Works

The build uses `bun2nix` (from nix-community) to provide offline, reproducible builds:

1. **bun.nix**: Pre-generated file (committed to version control) that contains all dependency fetch URLs and hashes
2. **bun2nix.fetchBunDeps**: Fetches all dependencies offline using the information in `bun.nix`
3. **bun2nix.hook**: Sets up Bun to use the offline cache during `bun install`
4. **Bun install**: Installs dependencies from the offline cache (no network access needed)
5. **Bun build**: Builds all packages using Bun's native workspace support

The build phase in `default.nix` runs:
1. `bun install --frozen-lockfile` (uses offline cache via bun2nix.hook)
2. `bun run build_cjs` to build all packages using workspace support

This provides:
- **Offline builds**: No network access required during Nix builds
- **Reproducibility**: All dependencies are pinned with hashes
- **Speed**: Bun's fast installs combined with Nix's binary cache

### Building

#### Build the binary for your system:
```bash
nix build
```

#### Build for a specific system:
```bash
nix build .#percy-cli
```

#### Build all layers:
```bash
nix build .#src-patched
nix build .#node-tree
nix build .#prepared-cli
nix build .#percy-cli
```

### Running Checks

Run all checks (builds all layers and verifies binary):
```bash
nix flake check
```

This will:
- Build all layers (src-patched, node-tree, prepared-cli, percy-cli)
- Verify the binary exists and is executable
- Run a smoke test (--version or --help)

#### Run specific checks:
```bash
nix build .#checks.aarch64-darwin.binary_exists
nix build .#checks.aarch64-darwin.binary_smoke_test
```

### Updating Dependencies

When dependencies change, you can use Nix apps to generate the required lockfiles:

#### Using Nix Apps (Recommended)

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

#### Using Bun Directly

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

### Required Files for Nix Builds

The following files must be present and committed for reproducible Nix builds:

1. **bun.lockb**: Bun's binary lockfile (generated by `bun install`)
   - Generate: `bun install` or `nix run .#bun-install`
   - Must be committed to version control

2. **bun.nix**: Pre-generated dependency cache for bun2nix
   - Generate: `bunx bun2nix -o bun.nix` or `nix run .#bun2nix-generate`
   - Must be committed to version control
   - Should be regenerated whenever `bun.lockb` changes

**Quick Update Command**:
```bash
nix run .#update-lockfiles
```

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
- Ensure Bun is using the correct Node.js version for compatibility
- Check that all required dependencies are installed

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

1. **Installed Vitest + jsdom**: Added vitest, @vitest/coverage-v8, jsdom
2. **Created Vitest configuration**: `vitest.config.mts` with jsdom environment
3. **Updated test helpers**: Adapted for Vitest (removed Karma-specific code)
4. **Updated test infrastructure**: Modified `scripts/test.js` to use Vitest for browser tests and Bun for node tests
5. **Removed Karma**: Deleted all Karma dependencies and `karma.config.cjs`
6. **Removed Rollup**: Deleted `rollup.config.js` and rollup config from package.json files
7. **Removed legacy dependencies**: Cleaned up nyc, cross-env, @nx/nx-darwin-arm64, @vitest/ui, and other unused packages

### Challenges and Solutions

#### 1. Test Framework Migration
- **Challenge**: Converting Jasmine tests to Vitest syntax
- **Solution**: Vitest's Jest-compatible API made migration straightforward
- **Impact**: Low - minimal test file updates needed

#### 2. Coverage Collection
- **Challenge**: Karma/nyc uses istanbul-lib-coverage, need equivalent
- **Solution**: Use Vitest's built-in v8 coverage provider for browser tests, Bun's built-in coverage for node tests
- **Impact**: Low - well-supported in both Vitest and Bun

#### 3. Test Helpers
- **Challenge**: Browser test helpers may need updates
- **Solution**: Migrated helpers to use Vitest's expect API
- **Impact**: Low - helper functions updated easily

#### 4. Browser Compatibility
- **Challenge**: jsdom doesn't distinguish between browsers
- **Solution**: Most tests work with jsdom; browser-specific tests can be handled separately if needed
- **Impact**: Low - jsdom covers most browser testing needs

## Testing & Verification

The following need to be tested to ensure they work correctly:

1. ✅ **Bun install**: Works correctly, generates `bun.lockb`
2. ✅ **bun.nix generation**: Works correctly via Nix apps
3. ⚠️ **Build process**: Needs verification that `bun run build` works for all packages
4. ⚠️ **Test execution**: Needs verification that `bun test` works with Bun's test runner
5. ⚠️ **Nix builds**: Needs verification that `nix build` works with bun2nix integration
6. ⚠️ **Workspace commands**: Needs verification that `bun run --filter` commands work as expected

## Notes

### Bun Workspace Commands
Bun's workspace filtering uses `--filter` flag:
- `bun run --filter './packages/*' build` - runs build in all packages
- `bun run --filter './packages/cli' build` - runs build in specific package

### Lockfile Management
- Bun uses `bun.lockb` (binary format) instead of `yarn.lock`
- `bun.nix` is generated using `bunx bun2nix -o bun.nix` and must be committed
- Both `bun.lockb` and `bun.nix` are required for reproducible Nix builds
- When dependencies change, regenerate both: `nix run .#update-lockfiles`

### Compatibility
- Bun is compatible with npm/yarn package.json format
- Existing build scripts work with Bun
- Tests may need minor adjustments for Bun's test runner

## Migration Benefits

### Completed Benefits
1. ✅ **Faster installs**: Bun installs 10-100x faster than Yarn
2. ✅ **Faster builds**: Bun bundler is very fast
3. ✅ **Simpler toolchain**: Reduced from Lerna + Yarn + Babel + Rollup + Karma + Jasmine + nyc to Bun + Vitest (11 devDependencies vs 20+)
4. ✅ **Better DX**: Faster feedback loops
5. ✅ **Native TypeScript**: No need for separate TS compilation
6. ✅ **Offline Nix builds**: bun2nix provides reproducible, offline builds
7. ✅ **Complete Rollup removal**: No more Rollup dependencies (Vite replaces it)
8. ✅ **Simpler test architecture**: No pre-bundling step needed
9. ✅ **Better browser testing**: Vitest + jsdom provides faster, simpler testing
10. ✅ **Native ESM support**: No more bundling step for browser tests
11. ✅ **Modern tooling**: Fully modernized toolchain

## Rollback Plan

If issues arise, you can rollback by:
1. Restore `lerna.json` from git history
2. Restore `yarn` in `dev-shell.nix` and `flake.nix`
3. Restore `lerna` in `package.json` devDependencies
4. Restore original scripts in `package.json`
5. Restore Babel/Rollup/Karma if needed

All changes are in version control, so rollback is straightforward.

## Related Documentation

- [Bun Documentation](https://bun.sh/docs)
- [bun2nix Documentation](https://github.com/nix-community/bun2nix)
- [Vitest Documentation](https://vitest.dev/)
- [jsdom Documentation](https://github.com/jsdom/jsdom)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
- [Percy CLI Development Guide](./packages/cli/README.md)
