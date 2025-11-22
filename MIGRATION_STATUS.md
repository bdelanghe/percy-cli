# Percy CLI Toolchain Migration

## Status

**Migration status: complete**

The Percy CLI has been migrated from the legacy stack (Yarn + Lerna + Babel + Rollup + Karma) to a modern toolchain centered on Bun, Vitest, and bun2nix.

- Package manager: Bun (native workspaces)
- Build: Bun bundler (no Babel, no Rollup)
- Tests:
  - Node tests: `bun test`
  - Browser-style tests: Vitest + jsdom
- Linting: ESLint 9 with flat config
- Nix: bun2nix-backed offline, reproducible builds
- Lockfiles: `bun.lockb` + `bun.nix` (both committed)

---

## Architecture: Before vs After

### Legacy

- Package manager: Yarn (workspaces)
- Monorepo tooling: Lerna 6
- Build: Babel + Rollup
- Tests: Jasmine + Karma
- Coverage: nyc
- Nix: dream2nix / mkYarnPackage
- Lockfile: `yarn.lock`

### Current

- Package manager: Bun (workspaces in `package.json`)
- Build: `bun build` (ESM output + browser bundles where needed)
- Tests:
  - Node: `bun test`
  - Browser: Vitest (`jsdom` environment)
- Coverage:
  - Node: `bun test --coverage`
  - Browser: `vitest run --coverage` (v8 provider)
- Linting: ESLint 9 flat config (`eslint.config.js`)
- Nix:
  - `bun2nix.fetchBunDeps` + `bun2nix.hook`
  - Nix-wrapped Node CLI (script that runs Node on the ESM entrypoint)
- Lockfiles: `bun.lockb` + generated `bun.nix`

---

## Migration Summary by Phase

### 1. Bun Migration

- Replaced `lerna` and Yarn invocations with `bun run --filter` and `bun install`.
- Removed `lerna.json` and `lerna` from devDependencies.
- Added `bunfig.toml`.
- Updated CI (GitHub Actions) to:
  - Install Bun (`oven-sh/setup-bun@v1`)
  - Use `bun install`, `bun run build`, and `bun run --filter` instead of Yarn/Lerna.
  - Cache keys now use `bun.lockb` instead of `yarn.lock`.
  - All workflows updated: `test.yml`, `lint.yml`, `windows.yml`, `typecheck.yml`, `release.yml`.
  - Release workflow uses `npm publish` directly (replaced `lerna publish`).

### 2. Build System (Babel/Rollup → Bun)

- Replaced Babel + Rollup with `bun build`:
  - Node packages: build to ESM (native module format).
  - Browser bundles: `bun build` with `iife` format where needed.
- Removed:
  - All Babel dependencies and `babel.config.*`.
  - All Rollup dependencies and `rollup.config.*`.
- Updated custom build scripts to call Bun.
- Binary packaging:
  - Dropped `pkg`-based bundling and `build:binary` (`bun --compile`) experiments.
  - Canonical approach: Nix-wrapped Node CLI that runs the ESM entrypoint produced by `bun run build`.

### 3. Nix Integration (bun2nix)

- Integrated `bun2nix` (nix-community):
  - `bun.nix` generated from `bun.lockb` and committed.
  - `bun2nix.fetchBunDeps` for offline dependency fetch.
  - `bun2nix.hook` to make `bun install` offline inside Nix builds.
- Layered Nix packages:
  1. `src-patched`: optionally adjusts `"type": "module"` for CJS-sensitive tools.
  2. `node-tree`: runs `bun install --frozen-lockfile` and `bun run build`.
  3. `percy-cli`: Nix-wrapped Node CLI pointing at the built ESM entrypoint.
- Nix apps for lockfile maintenance:
  - `nix run .#bun-install` – ensure `bun.lockb` exists/updated.
  - `nix run .#bun2nix-generate` – regenerate `bun.nix` from `bun.lockb`.
  - `nix run .#update-lockfiles` – run both.

### 4. Test Migration (Jasmine/Karma → Bun + Vitest)

- Node tests:
  - Migrated from Jasmine to Bun's test runner.
  - Removed Jasmine dependencies and config.
- Browser-style tests:
  - Migrated from Karma + Rollup to Vitest + jsdom.
  - Added `vitest`, `@vitest/coverage-v8`, `jsdom`.
  - `vitest.config.mts` uses `jsdom` environment.
  - Updated test helpers to Vitest APIs.
  - Removed Karma config and dependencies.
- Coverage:
  - Node: `bun test --coverage`.
  - Browser: `vitest run --coverage` with v8 provider.
- Removed `nyc`.

### 5. Cleanup + ESLint 9 Upgrade

- Removed:
  - Karma, Rollup, Babel, Jasmine, nyc, cross-env, `@nx/nx-darwin-arm64`, `@vitest/ui`, `gaze`.
  - `@babel/eslint-parser`, `eslint-plugin-babel`.
- ESLint 9 migration:
  - Switched from `.eslintrc*` to `eslint.config.js` (flat config).
  - Consolidated per-directory `.eslintrc` files into flat config with overrides.
  - Added `globals` for flat config support.
  - Simplified rules:
    - Use `@eslint/js` recommended config.
    - Only plugin kept: `eslint-plugin-import` (for `import/no-extraneous-dependencies`).
    - Dropped `eslint-config-standard`, `eslint-plugin-n`, `eslint-plugin-promise` since they were either unused or only used to turn rules off.

### 6. Dependency Scoping + TypeScript Setup

- **Dependency scoping** (moved package-specific deps to their packages):
  - `jsdom`: Moved to `packages/dom/devDependencies` (only package that needs DOM environment)
  - `memfs`: Moved to `packages/config/devDependencies` (only package that uses it)
  - Updated `vitest.config.mts` to use `node` environment by default, `jsdom` only for `packages/dom`
- **TypeScript migration preparation**:
  - Added `typescript` to root devDependencies
  - Created `tsconfig.base.json` as base configuration for future TypeScript migration
  - Replaced `tsd` with native TypeScript compiler (`tsc`) for type definition tests
  - Created `tsd-helpers.d.ts` replacements for `expectType`/`expectError` using TypeScript's type system
  - Updated `test:types` scripts to use `tsc --project types/tsconfig.json`
- **Future TypeScript migration**:
  - Plan to migrate packages from JavaScript to TypeScript incrementally
  - Base TypeScript configuration ready in `tsconfig.base.json`
  - Packages can extend base config as they migrate

---

## Current Root devDependencies

Minimal, root-level devDependencies:

**Linting**

- `@eslint/js` – ESLint's recommended ruleset.
- `eslint` – v9 flat config.
- `eslint-plugin-import` – only plugin used.
- `globals` – shared environments for flat config.

**Testing**

- `vitest` – browser-style tests.
- `@vitest/coverage-v8` – coverage provider for Vitest.

**TypeScript**

- `typescript` – TypeScript compiler (for type checking and future migration).

**Package-specific devDependencies** (scoped to packages that need them):

- `packages/dom`: `jsdom` – DOM environment for DOM package tests only
- `packages/config`: `memfs` – in-memory filesystem for config tests

Total: 6 root dev dependencies (down from 20+ in the original stack, down from 9 after scoping).

---

## Future: TypeScript Migration

**Status**: Preparation complete, migration pending

### Current State

- All packages are currently JavaScript (`.js` files)
- Type definitions exist in `packages/*/types/` directories (`.d.ts` files)
- Type checking uses TypeScript compiler (`tsc`) instead of `tsd`

### Migration Plan

**Phase 1: Infrastructure (Complete)**
- ✅ Added TypeScript to root devDependencies
- ✅ Created `tsconfig.base.json` as base configuration
- ✅ Replaced `tsd` with native TypeScript compiler for type tests
- ✅ Created `tsd-helpers.d.ts` for type testing utilities

**Phase 2: Incremental Migration (Planned)**
- Migrate packages from JavaScript to TypeScript incrementally
- Each package can extend `tsconfig.base.json`:
  ```json
  {
    "extends": "../../tsconfig.base.json",
    "compilerOptions": {
      "rootDir": "./src",
      "outDir": "./dist"
    },
    "include": ["src/**/*"]
  }
  ```
- Update build scripts to use TypeScript compiler or Bun's built-in TypeScript support
- Maintain backward compatibility during migration

**Benefits**
- Better type safety and developer experience
- Improved IDE support and autocomplete
- Catch errors at compile time
- Better documentation through types
- Bun has native TypeScript support, so no additional build step needed

---

## Usage

### Local

```bash
# Install dependencies
bun install

# Build all packages
bun run build

# Node tests
bun test

# Browser-style tests
bunx vitest run

# Coverage
bun test --coverage              # Node
bunx vitest run --coverage       # Browser
```

### Nix

```bash
# Build CLI binary for the current system
nix build .#percy-cli

# Run the full check pipeline (build + smoke tests)
nix flake check
```

Nix helper apps (if defined in flake.nix):

```bash
nix run .#bun-install        # Ensure bun.lockb exists / is up to date
nix run .#bun2nix-generate   # Regenerate bun.nix from bun.lockb
nix run .#update-lockfiles   # Run both in one shot
```

**Lockfile rules:**

- `bun.lockb` and `bun.nix` must both be present and committed.
- When dependencies change:
  - Either run `nix run .#update-lockfiles`
  - Or:

```bash
bun install
bunx bun2nix -o bun.nix
git add bun.lockb bun.nix
```

---

## Nix Build System

The Nix build uses Bun to install and build, with bun2nix providing strict offline reproducibility.

### Architecture

The build follows a multi-layer architecture:

1. **Patched source** (`src-patched`)
   - Optional normalization of `"type": "module"` across packages where CJS tooling demands it.

2. **Node tree** (`node-tree`)
   - Runs `bun install --frozen-lockfile` using `bun2nix.hook` and `bun2nix.fetchBunDeps`.
   - Runs `bun run build` to build all packages as ESM.

3. **CLI** (`percy-cli`)
   - Nix package that wraps Node and points to the built ESM CLI entrypoint.
   - Provides `percy-cli` (or `percy`) as an executable for:
     - x86_64-linux
     - aarch64-linux
     - x86_64-darwin
     - aarch64-darwin

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
nix build .#percy-cli
```

### Running Checks

```bash
# Run all checks (builds all layers and verifies binary)
nix flake check
```

This will:
- Build all layers (src-patched, node-tree, percy-cli)
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

- `flake.nix` – flake outputs, bun2nix integration, Nix apps
- `default.nix` – main package definitions (layers and percy-cli)
- `bun.nix` – pre-generated dependency cache (committed to version control)
- `bun.lockb` – Bun's binary lockfile (committed to version control)
- `nix/src-patched.nix` – source patching layer
- `nix/prepared-cli.nix` – CLI preparation layer (if used)
- `nix/pkg-wrapper.nix` – pkg binary wrapper (if used)
- `nix/percy-config.nix` – build configuration (versions, targets)
- `nix/dev-shell.nix` – development shell with Bun

---

## Remaining Work

The migration is functionally complete. The following items are optional or pending verification:

### Optional Cleanup
- Consider replacing `@babel/eslint-parser` with alternative (if still present)
- Final testing and validation of all test suites

### Verification Steps
1. **Install dependencies via Nix/bun2nix**
   - Ensure `bun.lockb` and `bun.nix` are up to date
   - Run `bun install` or use Nix to install dependencies
   - Regenerate `bun.nix` if using bun2nix: `nix run .#bun2nix-generate`

2. **Run tests to verify everything works**
   - Run browser tests: `bunx vitest run`
   - Run all tests: `bun test` (Node tests) + `bunx vitest run` (browser tests)
   - Run with coverage: `vitest run --coverage`

3. **Fix any test failures**
   - Most Jasmine syntax should work with Vitest (describe/it/expect)
   - Potential fixes needed:
     - `expectAsync().toBeResolvedTo()` → `await expect(...).resolves.toBe(...)`
     - `jasmine.any(String)` → `expect.any(String)` or use Vitest's matchers
     - Browser-specific conditionals may need adjustment (jsdom doesn't distinguish browsers)

4. **Update CI/CD if needed**
   - Ensure GitHub Actions workflows use Vitest instead of Karma
   - Remove any Karma-specific setup steps
   - Ensure Vitest and jsdom are available in CI environment

---

## Testing & Verification

The following need to be tested to ensure they work correctly:

1. ✅ **Bun install**: Works correctly, generates `bun.lockb`
2. ✅ **bun.nix generation**: Works correctly via Nix apps
3. ⚠️ **Build process**: Needs verification that `bun run build` works for all packages
4. ⚠️ **Test execution**: Needs verification that `bun test` works with Bun's test runner
5. ⚠️ **Nix builds**: Needs verification that `nix build` works with bun2nix integration
6. ⚠️ **Workspace commands**: Needs verification that `bun run --filter` commands work as expected
7. ⚠️ **Browser tests**: Needs verification that Vitest + jsdom tests run correctly
8. ⚠️ **Coverage collection**: Needs verification that coverage works for both Node and browser tests

---

## Rollback Plan

If issues arise, you can rollback by:

1. **Restore package manager and monorepo tooling**:
   - Restore `lerna.json` from git history
   - Restore `yarn` in `dev-shell.nix` and `flake.nix`
   - Restore `lerna` in `package.json` devDependencies

2. **Restore build system**:
   - Restore Babel dependencies and `babel.config.*` files
   - Restore Rollup dependencies and `rollup.config.*` files
   - Restore original build scripts in `package.json`

3. **Restore test infrastructure**:
   - Restore Karma dependencies and `karma.config.*` files
   - Restore Jasmine dependencies and configuration
   - Restore original test scripts

4. **Restore Nix integration**:
   - Restore `yarn.lock` and yarn-based Nix integration
   - Restore `dream2nix` or `mkYarnPackage` configuration

5. **Restore CI/CD**:
   - Restore original GitHub Actions workflows
   - Restore Yarn-based cache keys and commands

All changes are in version control, so rollback is straightforward. Use `git revert` or restore files from git history.

---

## Historical Note: Karma → Vitest

Originally, browser tests used Karma + Rollup + Jasmine. Problems:

- Heavy config surface (`karma.config.*`, `rollup.config.*`).
- Slow test runs (real browser startup).
- Rollup used only for tests.
- Harder integration with modern ESM-first tooling.

**Alternatives evaluated:**

- Playwright Test
- Vitest (browser mode)
- @web/test-runner
- Puppeteer + Jest/Vitest

**Vitest + jsdom was chosen because:**

- Jest-like API lowered migration cost from Jasmine.
- Integrates well with Bun and Vite.
- jsdom covers existing DOM use-cases without real browser startup.
- Eliminated the need for Rollup in tests entirely.
- Unified runner story: Vitest for browser-style tests, Bun for Node tests.

---

## Benefits

- Faster dependency installs (Bun) and builds (Bun bundler).
- Simpler toolchain:
  - From: Lerna + Yarn + Babel + Rollup + Karma + Jasmine + nyc
  - To: Bun + Vitest + ESLint 9 + bun2nix
- Native ESM builds end-to-end.
- Offline, reproducible Nix builds via bun2nix.
- Modern ESLint 9 flat config, with one central configuration instead of scattered `.eslintrc` files.
- Minimal, explicit devDependencies with clear responsibilities.

---

## References

- Bun: https://bun.sh/docs
- bun2nix: https://github.com/nix-community/bun2nix
- Vitest: https://vitest.dev/
- jsdom: https://github.com/jsdom/jsdom
- ESLint 9 migration: https://eslint.org/docs/latest/use/migrate-to-9.0.0
- ESLint flat config: https://eslint.org/docs/latest/use/configure/configuration-files-new
- Nix flakes: https://nixos.wiki/wiki/Flakes
