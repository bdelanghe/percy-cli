/* eslint-disable import/no-extraneous-dependencies */
import fs from 'fs';
import url from 'url';
import path from 'path';
import cp from 'child_process';
import parse from 'yargs-parser';
import colors from 'colors/safe.js';

const cwd = process.cwd();
const filename = url.fileURLToPath(import.meta.url);

process.env.NODE_ENV = 'test';

interface ParsedArgs {
  node?: boolean;
  browsers?: boolean;
  coverage?: boolean;
  reporter?: string;
  [key: string]: unknown;
}

// borrow yargs-parser to process command arguments
const argv = parse(process.argv.slice(2), {
  configuration: { 'strip-aliased': true },
  alias: { node: 'n', browsers: 'b', coverage: 'c', reporter: 'r' },
  boolean: ['node', 'browsers', 'coverage'],
  string: ['reporter']
}) as ParsedArgs;

interface SpawnOptions {
  cwd?: string;
  stdio?: 'inherit' | 'pipe' | 'ignore';
  env?: NodeJS.ProcessEnv;
  execArgv?: string[];
  [key: string]: unknown;
}

// promisified child_process util
function child(type: 'spawn' | 'fork' | 'exec', cmd: string, args: string[], options: SpawnOptions = {}): Promise<void> {
  if (type === 'exec') {
    // convert exec args to spawn args for better stdio handling
    const parts = cmd.split(' ');
    const newCmd = parts[0];
    const newArgs = [...parts.slice(1), ...args];
    type = 'spawn';
    cmd = newCmd;
    args = newArgs;
  }

  options = { stdio: 'inherit', ...options };
  args = args.filter(Boolean);

  return new Promise((resolve, reject) => {
    const proc = cp[type](cmd, args, options);
    proc.on('exit', (exitCode) => exitCode
      ? reject(Object.assign(new Error(`EEXIT ${exitCode}`), { exitCode }))
      : resolve());
    proc.on('error', reject);
  });
}

// util to turn a flags object into an array of flag strings and possible values
function flagify(flags: Record<string, unknown>, prefix = '', args: string[] = []): string[] {
  return Object.entries(flags).reduce((args, [key, val]) => {
    const push = (f: string, ...v: string[]) => args.includes(f) ? args : args.push(f, ...v);
    key = key.replace(/([a-z])([A-Z])/g, (_, l, u) => `${l}-${u.toLowerCase()}`);

    for (const v of [].concat(val as unknown)) {
      if (typeof v === 'object' && v !== null) {
        flagify(v as Record<string, unknown>, `${prefix}${key}.`, args);
      } else if (typeof v === 'boolean') {
        push(`--${v ? '' : 'no-'}${prefix}${key}`);
      } else if (v) {
        push(`--${prefix}${key}`, String(v));
      }
    }

    return args;
  }, args);
}

interface PackageJson {
  main?: string;
  browser?: string;
}

// main program
async function main({
  node,
  browsers,
  coverage,
  reporter
}: ParsedArgs = argv): Promise<void> {
  // determine arg defaults based on package.json values
  const pkg = JSON.parse(fs.readFileSync(path.join(cwd, 'package.json'), 'utf-8')) as PackageJson;
  const testNode = node != null ? node : (!browsers && pkg.main !== pkg.browser);
  const testBrowsers = browsers != null ? browsers : (!node && pkg.browser);

  if (!process.send) {
    // test runners assume they have control over the entire process, so give them each forks
    const flags = flagify({ coverage });
    const loader = url.pathToFileURL(path.resolve(filename, '../loader.ts')).href;
    const opts = { execArgv: ['--loader', loader, ...process.execArgv] };

    if (testNode) {
      await child('fork', filename, ['--node', ...flags], opts);
      process.stdout.write('\n');
    }

    if (testBrowsers) {
      await child('fork', filename, ['--browsers', ...flags], opts);
      process.stdout.write('\n');
    }
  } else if (testNode) {
    // $ bun test <cwd>/test/**/*.test.js
    console.log(colors.magenta('Running node tests with Bun...\n'));
    
    const bunBin = path.resolve(filename, '../../node_modules/.bin/bun');
    // Fallback to system bun if not found in node_modules
    const bunCmd = fs.existsSync(bunBin) ? bunBin : 'bun';
    
    // Bun test runner arguments
    const bunArgs = ['test'];
    
    // Add coverage flag if requested
    if (coverage) {
      bunArgs.push('--coverage');
    }
    
    // Add test files pattern
    const testPattern = path.join(cwd, 'test/**/*.test.js');
    bunArgs.push(testPattern);
    
    await child('spawn', bunCmd, bunArgs, {
      cwd: cwd,
      env: { ...process.env, NODE_ENV: 'test' }
    });
  } else if (testBrowsers) {
    // $ vitest run --config <root>/vitest.config.mts
    console.log(colors.magenta('Running browser tests with Vitest...'));
    
    const vitestBin = path.resolve(filename, '../../node_modules/.bin/vitest');
    const configFile = path.resolve(filename, '../../vitest.config.mts');
    
    // Run Vitest with coverage if requested
    const vitestArgs = ['run'];
    if (coverage) {
      vitestArgs.push('--coverage');
    }
    vitestArgs.push('--config', configFile);
    
    await child('spawn', vitestBin, vitestArgs, {
      cwd: cwd,
      env: { ...process.env, NODE_ENV: 'test' }
    });
  }
}

// handle errors
function handleError(err: Error & { exitCode?: number }): void {
  if (!err.exitCode) console.error(err);
  process.exit(err.exitCode || 1);
}

// run everything
main().catch(handleError);

