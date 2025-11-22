# Babel and Rollup Removal - Migration to Bun

## Completed Changes

### Build System
- ✅ **scripts/build.js**: Replaced Babel and Rollup with Bun's bundler
  - Node.js builds now use `bun build` with `--format cjs` for CommonJS output
  - Browser bundles now use `bun build` with `--format iife` for IIFE format
  - Preserves directory structure for Node.js builds
  - Handles browser bundle configuration from package.json `rollup` field

### Dependencies Removed
- ✅ Removed `@babel/cli`, `@babel/core`, `@babel/preset-env`, `@babel/register`
- ✅ Removed `babel-plugin-istanbul`, `babel-plugin-module-resolver`, `babel-plugin-transform-import-meta`
- ✅ Removed `rollup` and all `@rollup/plugin-*` packages
- ✅ Removed `karma-rollup-preprocessor`
- ⚠️ Kept `@babel/eslint-parser` (still needed for ESLint, can be replaced later)

### Configuration Files
- ✅ **babel.config.cjs**: Deleted (no longer used)
- ⚠️ **rollup.config.js**: Kept (still needed for Karma browser tests)
- ⚠️ **karma.config.cjs**: Still needed for browser tests (see below)
- ✅ **.eslintrc**: Updated with note about potential future parser change

### Scripts Updated
- ✅ **package.json build_cjs**: Now uses `bun run --filter './packages/*' build --node`
- ✅ **flake.nix**: Removed Babel step, now uses `bun run build_cjs`

## Remaining Work

### Test Scripts Updated
- ✅ **scripts/loader.js**: Removed Babel usage, now uses Bun's native module handling
- ✅ **scripts/test.js**: Removed babel-register.cjs reference, updated for Bun
- ✅ **scripts/babel-register.cjs**: Deleted (no longer needed)

### Karma for Browser Tests
- ⚠️ **Karma is still needed** for browser-based testing
- Bun's test runner doesn't run tests in actual browsers (Chrome/Firefox)
- The test system uses Karma to:
  - Run tests in real browsers (ChromeHeadless, FirefoxHeadless)
  - Bundle test files with Rollup (kept for browser tests only)
  - Collect coverage from browser tests

**Decision:** Keep Rollup only for Karma browser tests. Rollup and karma-rollup-preprocessor remain as dependencies for browser testing.

### Future: Complete Rollup Removal via Karma Migration

Once Karma is migrated to Playwright Test (see `KARMA_MIGRATION_PLAN.md`), Rollup can be **completely removed**:

- **Vite replaces Rollup**: Vite uses Rollup internally for production builds and provides a fast dev server for browser tests
- **No more karma-rollup-preprocessor**: Modern test runners (Playwright, Vitest browser mode) understand ES modules natively
- **Simpler architecture**: Playwright can run pure ESM test pages, or Vite can serve as the test server if transforms are needed
- **Complete cleanup**: After migration, `rollup.config.js` and all Rollup dependencies can be removed

**Migration Path:**
1. ✅ Remove Babel (completed)
2. ✅ Replace Rollup in build system with Bun (completed)
3. ⏳ Migrate Karma → Playwright Test (see `KARMA_MIGRATION_PLAN.md`)
4. ⏳ Remove Rollup entirely (after Karma migration)

## Testing Required

1. **Node.js builds**: Test that `bun run build` works for all packages
2. **Browser bundles**: Test that browser bundles are created correctly
3. **Build process**: Verify the build_cjs script works
4. **Nix builds**: Test that Nix builds work without Babel

## Notes

- Bun's bundler handles modern JS natively, so no transpilation config needed
- Bun can output CommonJS, ESM, or IIFE formats as needed
- The build script preserves file structure for Node.js builds
- Browser bundles use IIFE format with global names from package.json `rollup.output.name`

