# Percy CLI Migration Status

## Overview

This document tracks the migration from the legacy toolchain (Lerna + Yarn + Babel + Rollup + Karma) to modern tooling (Bun + bun2nix). This is a multi-phase migration that improves build performance, simplifies the toolchain, and modernizes the development experience.

## Migration Journey

### Original Architecture (Before Migration)
- **Package Manager**: Yarn (with workspaces)
- **Monorepo Tool**: Lerna 6.0.1
- **Build Tools**: Babel, Rollup
- **Test Runner**: Jasmine, Karma
- **Nix Integration**: dream2nix (nodejs-package-json-v3) + mkYarnPackage
- **Lock File**: yarn.lock

### Current Architecture (Partially Migrated)
- **Package Manager**: Bun ✅
- **Monorepo Tool**: Bun workspaces (native) ✅
- **Build Tools**: Bun bundler ✅ (Babel removed, Rollup kept only for Karma)
- **Test Runner**: Bun test runner ✅ (Node tests), Karma (browser tests - pending migration)
- **Nix Integration**: bun2nix from nix-community ✅
- **Lock File**: bun.lockb ✅

### Target Architecture (After Complete Migration)
- **Package Manager**: Bun
- **Monorepo Tool**: Bun workspaces (native)
- **Build Tools**: Bun bundler only (Babel and Rollup completely removed)
- **Test Runner**: Bun test runner (Node tests), Playwright Test (browser tests)
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
- ✅ **scripts/nix/executable.sh**: Updated `yarn install` → `bun install`, `yarn build` → `bun run build`

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
- ⚠️ **Kept**: `@babel/eslint-parser` (still needed for ESLint, can be replaced later)

#### Rollup Removal (Partial)
- ✅ **Build System**: Rollup removed from build system, replaced with Bun bundler
- ✅ **Dependencies Removed**: `rollup` and all `@rollup/plugin-*` packages from build system
- ⚠️ **Kept for Karma**: Rollup and `karma-rollup-preprocessor` kept only for browser tests
- ⚠️ **rollup.config.js**: Kept (still needed for Karma browser tests)

### Phase 3: Nix Integration Migration ✅

#### bun2nix Integration
- ✅ **flake.nix**: Migrated to bun2nix from nix-community (replaces custom Bun integration)
- ✅ **default.nix**: Updated to use `bun2nix.fetchBunDeps` and `bun2nix.hook` for offline builds
- ✅ **bun.nix**: Generated and committed (contains offline dependency cache)
- ✅ **dev-shell.nix**: Replaced `yarn` with `bun` in buildInputs
- ✅ **nix/src-patched.nix**: Removed bun.nix generation from postinstall (should be committed)
- ✅ **nix/percy-firefox.nix**: Updated to use `bun` instead of `yarn`
- ✅ **nix/offline-cache.nix**: Deleted (replaced by bun2nix)
- ✅ **nix/README.md**: Updated to document bun2nix-based architecture

#### Nix Apps for Lockfile Management
- ✅ **flake.nix apps**: Added Nix apps for generating lockfiles
  - `nix run .#bun-install` - Generate bun.lockb
  - `nix run .#bun2nix-generate` - Generate bun.nix from bun.lockb
  - `nix run .#update-lockfiles` - Update both lockfiles at once

### Phase 4: Test Infrastructure Updates ✅

#### Node.js Tests
- ✅ **package.json test scripts**: Updated to use `bun test` and `bun test --coverage`
- ✅ **Bun test runner**: Now used for Node.js tests (replaces Jasmine for Node tests)

## Current State

### What's Working
- ✅ Bun package management and workspace commands
- ✅ Bun bundler for Node.js and browser builds
- ✅ Bun test runner for Node.js tests
- ✅ bun2nix for offline, reproducible Nix builds
- ✅ All build scripts migrated to Bun

### What's Pending

#### Browser Testing (Karma → Playwright)
- ⏳ **Karma still in use**: Browser tests still use Karma + Rollup
- ⏳ **Rollup dependency**: Rollup kept only for `karma-rollup-preprocessor`
- ⏳ **Migration needed**: See "Remaining Work" section below

#### Dependencies Still Present
- ⚠️ **Karma packages**: `karma`, `karma-chrome-launcher`, `karma-firefox-launcher`, `karma-jasmine`, `karma-mocha-reporter`
- ⚠️ **Rollup for tests**: `rollup`, `karma-rollup-preprocessor` (only for Karma)
- ⚠️ **Jasmine**: Still in dependencies (used by Karma)
- ⚠️ **Babel ESLint parser**: `@babel/eslint-parser`, `eslint-plugin-babel` (for ESLint compatibility)

## Remaining Work

### Phase 5: Browser Testing Migration (Karma → Playwright)

**Status**: ⏳ Pending

**Goal**: Replace Karma + Rollup with Playwright Test for browser testing, enabling complete Rollup removal.

**Detailed Plan**: See [KARMA_MIGRATION_PLAN.md](./KARMA_MIGRATION_PLAN.md) for comprehensive migration details.

**Why Playwright?**
- Modern, actively maintained by Microsoft
- Excellent browser automation and testing
- Built-in test runner (no separate framework needed)
- Great debugging tools (UI mode, trace viewer)
- Supports multiple browsers (Chromium, Firefox, WebKit)
- Better performance than Karma
- Built-in coverage support
- Can run tests in parallel

**Migration Overview**:

1. **Research and Preparation** - Audit tests, create proof of concept
2. **Setup and Configuration** - Install Playwright, configure browsers
3. **Test Migration** - Convert Jasmine tests to Playwright syntax
4. **Build System Updates** - Remove Rollup completely
5. **Cleanup** - Remove Karma dependencies and config files

**Estimated Timeline**: 2-3 weeks

**Benefits After Migration**:
- Complete Rollup removal
- Simpler architecture (no pre-bundling step)
- Better performance
- Modern tooling
- Native ESM support

### Phase 6: Final Cleanup

**Status**: ⏳ Pending (after Karma migration)

**Tasks**:
- Remove all Karma dependencies
- Remove all Rollup dependencies
- Remove `rollup.config.js`
- Remove `karma.config.cjs`
- Consider replacing `@babel/eslint-parser` with alternative
- Update all documentation
- Final testing and validation

## Required Files for Nix Builds

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

## Testing Required

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
3. ✅ **Simpler toolchain**: Reduced from Lerna + Yarn + Babel + Rollup to Bun
4. ✅ **Better DX**: Faster feedback loops
5. ✅ **Native TypeScript**: No need for separate TS compilation
6. ✅ **Offline Nix builds**: bun2nix provides reproducible, offline builds

### Future Benefits (After Karma Migration)
1. **Complete Rollup removal**: No more Rollup dependencies
2. **Simpler test architecture**: No pre-bundling step needed
3. **Better browser testing**: Playwright provides better debugging and tooling
4. **Native ESM support**: No more bundling step for browser tests
5. **Modern tooling**: Fully modernized toolchain

## Rollback Plan

If issues arise, you can rollback by:
1. Restore `lerna.json` from git history
2. Restore `yarn` in `dev-shell.nix` and `flake.nix`
3. Restore `lerna` in `package.json` devDependencies
4. Restore original scripts in `package.json`
5. Restore Babel/Rollup if needed

All changes are in version control, so rollback is straightforward.

## Related Documentation

- [Karma Migration Plan](./KARMA_MIGRATION_PLAN.md) - Detailed plan for migrating browser tests from Karma to Playwright
- [Nix Build System Documentation](./nix/README.md)
- [Bun Documentation](https://bun.sh/docs)
- [bun2nix Documentation](https://github.com/nix-community/bun2nix)
- [Playwright Test Documentation](https://playwright.dev/docs/test-intro)

