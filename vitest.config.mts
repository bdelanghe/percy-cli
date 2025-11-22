import { defineConfig } from 'vitest/config';
import path from 'path';
import { fileURLToPath } from 'url';
import { existsSync } from 'fs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const CWD = process.cwd();

// Check if we're in a package that needs browser tests (dom, sdk-utils)
const needsBrowserTests = CWD.includes(path.join('packages', 'dom')) || 
                          CWD.includes(path.join('packages', 'sdk-utils'));

// Match Karma's basePath behavior - config is per-package (process.cwd() when run from package)
export default defineConfig({
  root: CWD,

  test: {
    // Match Karma's test glob
    include: ['test/**/*.test.js'],
    exclude: [
      'test/request.test.js',
      'test/proxy.test.js',
    ],

    // Use jsdom for packages that need browser tests, node for everything else
    environment: needsBrowserTests ? 'jsdom' : 'node',

    // Hook in test helpers - check for package-level helpers first, then root
    setupFiles: (() => {
      const setupFiles: string[] = [];
      // Try package-level test-helpers first (if exists)
      const pkgHelpers = path.resolve(CWD, 'test/helpers.js');
      if (existsSync(pkgHelpers)) {
        setupFiles.push(pkgHelpers);
      }
      // Always include root test-helpers
      const rootHelpers = path.resolve(ROOT, 'scripts/test-helpers.js');
      if (existsSync(rootHelpers)) {
        setupFiles.push(rootHelpers);
      }
      return setupFiles;
    })(),

    // Match Karma's reporter style
    reporters: ['default'],

    // Single run by default (match Karma's singleRun: true)
    watch: false,

    // Match Karma's timeout behavior
    testTimeout: process.platform === 'win32' ? 25000 : 10000,

    // Coverage configuration
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      exclude: [
        'node_modules/**',
        'test/**',
        '**/*.test.js',
        '**/*.config.*',
      ],
    },
  },

  // Vite handles bundling (replaces rollupPreprocessor)
  resolve: {
    alias: {
      // Vite automatically resolves @percy/* packages via node_modules
      // The LOADER_ALIAS from scripts/loader.js was for Rollup's custom resolution
      // Vite's default resolution should work for workspace packages
    },
  },

  define: {
    // Replicate Karma's client.env
    'process.env.DUMP_FAILED_TEST_LOGS': JSON.stringify(
      process.env.DUMP_FAILED_TEST_LOGS ?? ''
    ),
    // Provide process.env for browser context (like rollup did)
    'process.env.__PERCY_BROWSERIFIED__': 'true',
  },
});

