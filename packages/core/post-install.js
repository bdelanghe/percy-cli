import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

// Helper to safely import logger, handling both built and source scenarios
async function getLogger() {
  try {
    // Try importing from dist first (production/after build)
    const { logger } = await import('@percy/logger');
    return logger('core:post-install');
  } catch (distError) {
    // If dist doesn't exist, try importing from source using file path
    try {
      const __dirname = path.dirname(fileURLToPath(import.meta.url));
      const loggerPath = path.resolve(__dirname, '../../logger/src/index.ts');
      if (fs.existsSync(loggerPath)) {
        const loggerModule = await import(`file://${loggerPath}`);
        return loggerModule.default('core:post-install');
      }
    } catch (srcError) {
      // Fall back to console if both fail
    }
    // Fallback to console logger
    return {
      error: (...args) => console.error('[core:post-install]', ...args)
    };
  }
}

try {
  if (!['false', '0', undefined].includes(process.env.PERCY_POSTINSTALL_BROWSER)) {
    // Automatically download and install Chromium if PERCY_POSTINSTALL_BROWSER is set
    await import('./dist/install.js').then(install => install.chromium());
  } else if (!process.send && fs.existsSync('./src')) {
    // In development, fork this script with the development loader and always install
    await import('child_process').then(cp => cp.fork('./post-install.js', {
      execArgv: ['--no-warnings', '--loader=../../scripts/loader.js'],
      env: { PERCY_POSTINSTALL_BROWSER: true }
    }));
  }
} catch (error) {
  const log = await getLogger();
  log.error('Encountered an error while installing Chromium');
  log.error(error);
}
