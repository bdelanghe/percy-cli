import fs from 'fs';
import os from 'os';
import path from 'path';
import { vi } from 'vitest';

// Reset various global @percy/config internals for testing
export async function resetPercyConfig(all) {
  // aliased to src during tests
  let { clearMigrations } = await import('../dist/migrate.js');
  let { resetSchema } = await import('../dist/validate.js');
  let { cache } = await import('../dist/load.js');
  if (all) clearMigrations();
  if (all) resetSchema();
  cache.clear();
}

// When mocking fs, these classes should not be spied on
const FS_CLASSES = [
  'Stats', 'Dirent',
  'StatWatcher', 'FSWatcher',
  'ReadStream', 'WriteStream'
];

// Mock and spy on fs methods using a temporary directory
export async function mockfs({
  // list of filepaths or function matchers to allow direct access to the real filesystem
  $bypass = [],
  // initial flat map of files and/or directories to create
  ...initial
} = {}) {
  // Create a temporary directory for test files
  const testDir = fs.mkdtempSync(path.join(os.tmpdir(), 'percy-config-test-'));
  const originalCwd = process.cwd();
  
  // Change to test directory
  process.chdir(testDir);

  // Create initial files/directories
  for (const [filepath, content] of Object.entries(initial)) {
    const fullPath = path.resolve(testDir, filepath);
    const dir = path.dirname(fullPath);
    
    if (content === null) {
      // Directory
      fs.mkdirSync(fullPath, { recursive: true });
    } else {
      // File
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(fullPath, content);
    }
  }

  // automatically cleanup mock imports
  global.__MOCK_IMPORTS__?.clear();

  // Spy on fs methods to track calls (for test assertions)
  // We don't mock them, just track them - tests use real filesystem in temp dir
  const spies = {};
  const installSpies = (fsObj) => {
    for (const k in fsObj) {
      if (typeof fsObj[k] === 'function' && !FS_CLASSES.includes(k)) {
        if (!spies[k]) {
          spies[k] = vi.spyOn(fsObj, k);
        }
      }
    }
  };

  installSpies(fs);
  installSpies(fs.promises);

  // Store cleanup function
  const cleanup = () => {
    // Restore original cwd
    process.chdir(originalCwd);
    // Clean up temp directory
    try {
      fs.rmSync(testDir, { recursive: true, force: true });
    } catch (err) {
      // Ignore cleanup errors
    }
    // Restore spies
    Object.values(spies).forEach(spy => spy.mockRestore());
  };

  // Attach cleanup to fs for afterEach hooks
  fs.$cleanup = cleanup;
  fs.$testDir = testDir;

  return {
    cleanup,
    testDir,
    // For compatibility with old code that accessed vol
    fromJSON: () => {},
    writeFileSync: fs.writeFileSync,
    readFileSync: fs.readFileSync,
    existsSync: fs.existsSync,
    mkdirSync: fs.mkdirSync,
    rmSync: fs.rmSync
  };
}

// export fs for convenience
export { fs };
