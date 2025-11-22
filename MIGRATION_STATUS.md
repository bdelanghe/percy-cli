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
- `jsdom` – DOM-like environment for Vitest (configured in `vitest.config.mts`).

**Test utilities**

- `memfs` – in-memory filesystem (used in `packages/config/test/helpers.js`).
- `tsd` – tests of TypeScript definitions (`*.test-d.ts`).

Total: 9 dev dependencies (down from 20+ in the original stack).

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

## Nix Build Overview

The Nix build uses Bun to install and build, with bun2nix providing strict offline reproducibility.

### Layers

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

### Key Files

- `flake.nix` – flake outputs, bun2nix integration, Nix apps.
- `default.nix` – main package definitions (layers and percy-cli).
- `bun.lockb` – Bun lockfile (binary).
- `bun.nix` – bun2nix dependency mapping (generated from bun.lockb).
- `nix/src-patched.nix` – patch layer.
- `nix/dev-shell.nix` – development shell with Bun.

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
