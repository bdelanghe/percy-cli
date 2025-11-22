# Karma to Modern Browser Testing Migration Plan

## Overview

This document outlines the migration from Karma + Rollup + Jasmine to a modern browser testing solution. Karma is currently used for browser-based testing, but modern alternatives offer better performance, simpler configuration, and better integration with modern tooling.

## Current Architecture

### Current Setup
- **Test Runner**: Karma 6.0.2
- **Test Framework**: Jasmine 4.0.0
- **Bundler**: Rollup (via karma-rollup-preprocessor)
- **Browsers**: ChromeHeadless, FirefoxHeadless
- **Coverage**: Istanbul/nyc (via istanbul-lib-coverage)
- **Configuration**: `karma.config.cjs` + `rollup.config.js`

### Current Features
- Runs tests in real browsers (Chrome, Firefox)
- Bundles test files with Rollup
- Collects coverage from browser tests
- Supports test helpers and assets
- Excludes Node.js-specific tests (request.test.js, proxy.test.js)
- Custom preprocessors for different file types

### Current Dependencies
```json
{
  "karma": "^6.0.2",
  "karma-chrome-launcher": "^3.1.0",
  "karma-firefox-launcher": "^2.1.1",
  "karma-jasmine": "^5.0.0",
  "karma-mocha-reporter": "^2.2.5",
  "karma-rollup-preprocessor": "^7.0.5",
  "jasmine": "^4.0.0",
  "jasmine-spec-reporter": "^7.0.0"
}
```

## Modern Alternatives

### Option 1: Playwright Test (Recommended)

**Pros:**
- Modern, actively maintained by Microsoft
- Excellent browser automation and testing
- Built-in test runner (no separate framework needed)
- Great debugging tools (UI mode, trace viewer)
- Supports multiple browsers (Chromium, Firefox, WebKit)
- Better performance than Karma
- Built-in coverage support
- Can run tests in parallel
- Excellent documentation and community

**Cons:**
- Different API from Jasmine (would need test migration)
- Requires learning new APIs
- Heavier than some alternatives

**Migration Complexity:** Medium-High (test rewrite needed)

### Option 2: Vitest with Browser Mode

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
- Browser mode is still experimental in some respects

**Migration Complexity:** Medium (test rewrite needed, but similar to Jest)

**Note:** If choosing Vitest, Vite becomes the bundler/transformer layer, eliminating the need for Rollup entirely.

### Option 3: Web Test Runner (@web/test-runner)

**Pros:**
- Modern, lightweight alternative to Karma
- Minimal configuration
- Uses native ES modules (no bundling needed)
- Supports multiple browsers
- Good performance
- Can keep existing test structure

**Cons:**
- Smaller community than Playwright
- Less feature-rich than Playwright
- May need some test adjustments

**Migration Complexity:** Low-Medium (minimal test changes)

### Option 4: Puppeteer + Jest/Vitest

**Pros:**
- Puppeteer is mature and well-documented
- Can use Jest/Vitest for test framework
- Good browser control

**Cons:**
- Requires manual browser management
- More setup complexity
- Puppeteer only supports Chromium (not Firefox)

**Migration Complexity:** Medium-High

## Recommendation: Playwright Test

**Why Playwright:**
1. Best long-term solution with active development
2. Excellent debugging and tooling
3. Supports all major browsers
4. Better performance and reliability
5. Great for visual testing (which aligns with Percy's mission)
6. Can potentially integrate with Percy's own testing infrastructure

## Migration Plan

### Phase 1: Research and Preparation

1. **Audit current browser tests**
   - List all packages with browser tests
   - Document test patterns and helpers used
   - Identify browser-specific test requirements
   - Note any Karma-specific features being used

2. **Create proof of concept**
   - Migrate one simple test file to Playwright
   - Verify coverage collection works
   - Test with Bun's test runner integration
   - Validate browser compatibility

3. **Plan test migration strategy**
   - Decide on test organization (separate files vs. shared)
   - Plan helper function migration
   - Design coverage collection approach

### Phase 2: Setup and Configuration

1. **Install Playwright**
   ```bash
   bun add -d @playwright/test
   bunx playwright install
   ```

2. **Create Playwright configuration**
   - `playwright.config.js` for root-level config
   - Per-package configs if needed
   - Configure browsers (Chrome, Firefox)
   - Set up coverage collection
   - Configure test file patterns

3. **Update package.json scripts**
   - Add `test:browser` script using Playwright
   - Update `test` script to run both Node and browser tests
   - Update coverage scripts

### Phase 3: Test Migration

1. **Migrate test helpers**
   - Update `test/helpers.js` for Playwright context
   - Migrate browser-specific utilities
   - Update test setup/teardown

2. **Migrate test files**
   - Convert Jasmine syntax to Playwright test syntax
   - Update assertions (Jasmine → Playwright expect)
   - Migrate async/await patterns
   - Update browser API usage

3. **Handle special cases**
   - Test assets and file serving
   - Mock implementations
   - Browser-specific test exclusions
   - Coverage collection

### Phase 4: Build System Updates

1. **Remove Rollup dependency completely**
   - **Vite replaces Rollup**: Vite uses Rollup internally for production builds and provides a fast dev server
   - **No more karma-rollup-preprocessor**: Playwright understands ES modules natively
   - **Simpler architecture**: Playwright can run pure ESM test pages, or Vite can serve as test server if transforms are needed
   - **Complete cleanup**: Remove `rollup.config.js` and all Rollup dependencies after migration

2. **Update build scripts**
   - Remove Karma-specific build steps
   - Remove Rollup from test infrastructure
   - Update test scripts in package.json
   - Update CI/CD workflows

### Phase 5: Cleanup

1. **Remove Karma dependencies**
   - Remove karma packages from package.json
   - Remove karma.config.cjs
   - Clean up rollup.config.js (if only used for Karma)

2. **Update documentation**
   - Update CONTRIBUTING.md
   - Update README.md
   - Document new test commands

3. **Update CI/CD**
   - Update GitHub Actions to use Playwright
   - Install Playwright browsers in CI
   - Update test commands

## Vite Replaces Rollup for Browser Tests

**Key Insight**: Vite can replace Rollup for almost everything Rollup is used for in Karma today.

### How Vite Replaces Rollup

1. **Vite uses Rollup internally**: Vite's production build pipeline is Rollup with a configuration layer
2. **For browser tests, Vite simplifies everything**:
   - Modern test runners (Playwright, Vitest) understand ES modules natively
   - No more pre-bundling step required
   - No more `karma-rollup-preprocessor`
   - Vite becomes the dev server + transformer if needed

3. **With Playwright**:
   - Playwright can run pure ESM test pages (no bundler needed)
   - If transforms are needed (TS → JS, JSX, module aliases, PostCSS, ENV vars), Vite slots in naturally as the test server

4. **With Vitest Browser Mode**:
   - Vite is the engine (Vitest is built on Vite like Jest is built on its transformer)
   - Full Vite capabilities available

### What This Means

- ✅ **Complete Rollup removal possible**: After Karma migration, Rollup can be fully removed
- ✅ **Simpler architecture**: No more separate bundling step for tests
- ✅ **Better performance**: Native ESM support means faster test execution
- ✅ **Modern tooling**: Vite provides Rollup's capabilities with better DX

## Implementation Details

### Playwright Configuration Example

```javascript
// playwright.config.js
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './test',
  testMatch: /.*\.test\.js$/,
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },
  ],
  webServer: {
    command: 'bun run serve',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
  },
});
```

### Test Migration Example

**Before (Jasmine/Karma):**
```javascript
describe('MyComponent', () => {
  it('should render correctly', () => {
    const element = document.createElement('div');
    element.innerHTML = '<span>Hello</span>';
    expect(element.querySelector('span').textContent).toBe('Hello');
  });
});
```

**After (Playwright):**
```javascript
import { test, expect } from '@playwright/test';

test('should render correctly', async ({ page }) => {
  await page.setContent('<div><span>Hello</span></div>');
  const text = await page.textContent('span');
  expect(text).toBe('Hello');
});
```

### Coverage Collection

Playwright supports coverage via:
1. **babel-plugin-istanbul** or **@vitest/coverage-v8**
2. **Playwright's built-in coverage** (experimental)
3. **Custom coverage collection** using browser DevTools Protocol

Example with Vitest coverage:
```javascript
// vitest.config.js
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    browser: {
      enabled: true,
      name: 'chromium',
      provider: 'playwright',
    },
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
    },
  },
});
```

## Challenges and Considerations

### 1. Test Framework Migration
- **Challenge**: Converting Jasmine tests to Playwright syntax
- **Solution**: Create migration script or do incremental migration
- **Impact**: Medium - requires test file updates

### 2. Coverage Collection
- **Challenge**: Karma uses istanbul-lib-coverage, need equivalent
- **Solution**: Use Vitest coverage or Playwright's coverage API
- **Impact**: Low - well-supported in modern tools

### 3. Test Helpers
- **Challenge**: Browser test helpers may need updates
- **Solution**: Migrate helpers to use Playwright's page API
- **Impact**: Medium - helper functions need updates

### 4. Asset Serving
- **Challenge**: Karma serves test assets, need equivalent
- **Solution**: Use Playwright's webServer or static file serving
- **Impact**: Low - Playwright has built-in support

### 5. Browser Compatibility
- **Challenge**: Ensure all browsers still supported
- **Solution**: Playwright supports Chrome, Firefox, WebKit
- **Impact**: Low - better browser support than Karma

### 6. CI/CD Integration
- **Challenge**: Update GitHub Actions workflows
- **Solution**: Use Playwright's GitHub Actions setup
- **Impact**: Low - straightforward migration

## Rollback Plan

If issues arise:
1. Keep Karma config files in git history
2. Restore Karma dependencies
3. Revert test script changes
4. Restore CI/CD workflows

## Timeline Estimate

- **Phase 1 (Research)**: 1-2 days
- **Phase 2 (Setup)**: 1-2 days
- **Phase 3 (Migration)**: 1-2 weeks (depending on test count)
- **Phase 4 (Build Updates)**: 1-2 days
- **Phase 5 (Cleanup)**: 1 day

**Total**: 2-3 weeks for complete migration

## Benefits After Migration

1. **Better Performance**: Playwright is faster than Karma
2. **Simpler Configuration**: Less config files, clearer setup
3. **Better Debugging**: Playwright's UI mode and trace viewer
4. **Modern Tooling**: Better integration with Bun and modern JS
5. **Reduced Dependencies**: Remove Karma, Rollup (for tests), and related packages
6. **Better CI/CD**: Simpler GitHub Actions setup
7. **Future-Proof**: Playwright is actively maintained and modern
8. **Complete Rollup Removal**: Vite replaces Rollup for browser tests, allowing full removal of Rollup dependencies
9. **Native ESM Support**: No more pre-bundling step needed for browser tests

## Questions to Answer

1. **Do we need to keep Rollup for anything else?**
   - ✅ **Answer**: Rollup is only used for Karma tests (build system uses Bun)
   - ✅ **After migration**: Rollup can be completely removed
   - ✅ **Vite replaces Rollup**: Vite uses Rollup internally, so we get Rollup's capabilities via Vite if needed

2. **Can we use Bun's test runner for browser tests?**
   - Bun's test runner doesn't support browser testing yet
   - Need Playwright or similar for browser tests

3. **Should we migrate all tests at once or incrementally?**
   - Incremental is safer but requires maintaining both systems temporarily
   - All at once is faster but riskier

4. **Do we need to support all browsers Karma currently supports?**
   - Currently: Chrome, Firefox
   - Playwright supports: Chromium, Firefox, WebKit
   - Should we add WebKit testing?

## Next Steps

1. Review and approve this migration plan
2. Create proof of concept with one test file
3. Evaluate Playwright vs. other options
4. Begin Phase 1 (Research and Preparation)
5. Set up migration timeline and milestones

