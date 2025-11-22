/* eslint-disable import/no-extraneous-dependencies */
import { expect } from 'vitest';

// Vitest Browser Mode: Set default timeout (Vitest uses testTimeout in config, but we can also set it here)
// The timeout is set in vitest.config.mts, but we keep this for compatibility

// Vitest Browser Mode: Add custom matchers using expect.extend()
expect.extend({
  // If any property within the path is not defined, it will show a failure rather than error
  // about accessing a property of an undefined value.
  toHaveProperty(received, path, expected) {
    const value = path.split('.').reduce((v, k) => v && v[k], received);
    const pass = typeof expected === 'undefined'
      ? typeof value !== 'undefined'
      : this.equals(value, expected);
    
    if (pass) {
      return {
        message: () => `Expected ${this.utils.printReceived(path)} not to equal ${this.utils.printExpected(expected)}`,
        pass: true,
      };
    } else {
      return {
        message: () => `Expected ${this.utils.printReceived(path)} to equal ${this.utils.printExpected(expected)}, but was ${this.utils.printReceived(value)}`,
        pass: false,
      };
    }
  },

  // Vitest's toContain already handles Sets properly, but we keep this for compatibility
  // Note: Vitest's built-in toContain is more robust, so this may not be needed
});

// dump logs for failed tests when debugging
// Vitest Browser Mode: process.env is available in browser context via Vite's define
const { DUMP_FAILED_TEST_LOGS } = process.env;

// Vitest Browser Mode: Handle failed test logs via afterEach hook
if (process.env.DUMP_FAILED_TEST_LOGS) {
  // Vitest Browser Mode doesn't have the same reporter API, so we use afterEach
  // This will be called after each test
  if (typeof afterEach !== 'undefined') {
    afterEach(async () => {
      // Check if test failed - Vitest exposes test state differently
      // For now, we'll dump logs on any test (can be refined)
      try {
        const logger = (await import('@percy/logger/test/helpers')).logger;
        if (logger) {
          // In Vitest Browser Mode, we'd need to check test status differently
          // For now, just dump if logger has errors
          logger.dump();
        }
      } catch (e) {
        // Ignore if logger not available
      }
    });
  }
}
