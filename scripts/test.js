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

// borrow yargs-parser to process command arguments
const argv = parse(process.argv.slice(2), {
  configuration: { 'strip-aliased': true },
  alias: { node: 'n', browsers: 'b', coverage: 'c', reporter: 'r', watch: 'w' },
  boolean: ['node', 'browsers', 'coverage', 'watch'],
  array: ['karma.browsers', 'karma.reporters'],
  string: ['reporter']
});

// promisified child_process util
function child(type, cmd, args, options) {
  if (type === 'exec') {
    // convert exec args to spawn args for better stdio handling
    [type, cmd, args, options] = cmd.split(' ').reduce((args, word) => (
      args[1] ? args[2].push(word) : (args[1] = word)
    ) && args, ['spawn', '', [], args]);
  }

  options = { stdio: 'inherit', ...options };
  args = args.filter(Boolean);

  return new Promise((resolve, reject) => {
    cp[type](cmd, args, options)
      .on('exit', exitCode => exitCode
        ? reject(Object.assign(new Error(`EEXIT ${exitCode}`), { exitCode }))
        : resolve())
      .on('error', reject);
  });
}

// util to turn a flags object into an array of flag strings and possible values
function flagify(flags, prefix = '', args = []) {
  return Object.entries(flags).reduce((args, [key, val]) => {
    let push = (f, ...v) => args.includes(f) ? args : args.push(f, ...v);
    key = key.replace(/([a-z])([A-Z])/g, (_, l, u) => `${l}-${u.toLowerCase()}`);

    for (let v of [].concat(val)) {
      if (typeof v === 'object') {
        flagify(v, `${prefix}${key}.`, args);
      } else if (typeof v === 'boolean') {
        push(`--${v ? '' : 'no-'}${prefix}${key}`);
      } else if (v) {
        push(`--${prefix}${key}`, v);
      }
    }

    return args;
  }, args);
}

// main program
async function main({
  node,
  browsers,
  coverage,
  reporter,
  karma: karmaArgs
} = argv) {
  // determine arg defaults based on package.json values
  let pkg = JSON.parse(fs.readFileSync(path.join(cwd, 'package.json')));
  let testNode = node != null ? node : (!browsers && pkg.main !== pkg.browser);
  let testBrowsers = browsers != null ? browsers : (!node && pkg.browser);

  if (coverage) {
    // $ rimraf <cwd>/{.nyc_output,coverage} || true &&
    //   nyc --silent --no-clean node <root>/test.js ... &&
    //   nyc report --reporter <reporter>
    let flags = flagify({ node, browsers });
    let nycbin = path.resolve(filename, '../../node_modules/.bin/nyc');
    let { default: rimraf } = await import('rimraf');

    await new Promise(r => rimraf(path.join(cwd, '{.nyc_output,coverage}'), r));
    await child('spawn', nycbin, ['--silent', '--no-clean', 'node', filename, ...flags]);
    await child('spawn', nycbin, ['report', '--check-coverage', ...flagify({ reporter })]);
  } else if (!process.send) {
    // test runners assume they have control over the entire process, so give them each forks
    let flags = flagify({ coverage, karma: karmaArgs });
    let loader = url.pathToFileURL(path.resolve(filename, '../loader.js')).href;
    let opts = { execArgv: ['--loader', loader, ...process.execArgv] };

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
    
    let bunBin = path.resolve(filename, '../../node_modules/.bin/bun');
    // Fallback to system bun if not found in node_modules
    let bunCmd = fs.existsSync(bunBin) ? bunBin : 'bun';
    
    // Bun test runner arguments
    let bunArgs = ['test'];
    
    // Add test files pattern
    let testPattern = path.join(cwd, 'test/**/*.test.js');
    bunArgs.push(testPattern);
    
    await child('spawn', bunCmd, bunArgs, {
      cwd: cwd,
      env: { ...process.env, NODE_ENV: 'test' }
    });
  } else if (testBrowsers) {
    // $ vitest run --config <root>/vitest.config.mts
    console.log(colors.magenta('Running browser tests with Vitest...'));
    
    let vitestBin = path.resolve(filename, '../../node_modules/.bin/vitest');
    let configFile = path.resolve(filename, '../../vitest.config.mts');
    
    // Run Vitest with coverage if requested
    let vitestArgs = ['run'];
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
function handleError(err) {
  if (!err.exitCode) console.error(err);
  if (!argv.watch) process.exit(err.exitCode || 1);
}

// run everything and maybe watch for changes
main().catch(handleError).then(() => argv.watch && (
  import('./watch').then(w => w.watch(() => main().catch(handleError)))
));
