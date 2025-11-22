#!/usr/bin/env bun

// Bun-compiled binary entrypoint for Percy CLI
// This file is compiled with `bun build --compile` to create a standalone executable

import { percy, checkForUpdate } from './index.js';

// Run the CLI
(async () => {
  await checkForUpdate();
  await percy(process.argv.slice(2));
})();

