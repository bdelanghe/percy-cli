/* eslint-disable import/no-extraneous-dependencies */
import fs from 'fs';
import path from 'path';
import colors from 'colors';
import arg from 'arg';
import { spawn, ChildProcess } from 'child_process';

const cwd = process.cwd();
process.env.NODE_ENV = 'production';

interface ParsedArgs {
  node?: boolean;
  bundle?: boolean;
  watch?: boolean;
  [key: string]: unknown;
}

// parse command arguments using arg (lightweight alternative to yargs-parser)
const args = arg(
  {
    '--node': Boolean,
    '--bundle': Boolean,
    '--watch': Boolean,
    '-n': '--node',
    '-b': '--bundle',
    '-w': '--watch',
  },
  {
    argv: process.argv.slice(2),
    permissive: false,
  }
);

// Convert to expected format (camelCase without -- prefix)
// arg returns undefined for flags that aren't present, which matches yargs-parser behavior
const argv: ParsedArgs = {
  node: args['--node'],
  bundle: args['--bundle'],
  watch: args['--watch'],
};

interface SpawnOptions {
  cwd?: string;
  stdio?: 'inherit' | 'pipe' | 'ignore';
  env?: NodeJS.ProcessEnv;
  [key: string]: unknown;
}

// promisified spawn
function bunSpawn(args: string[], options: SpawnOptions = {}): Promise<void> {
  return new Promise((resolve, reject) => {
    const proc: ChildProcess = spawn('bun', args, { stdio: 'inherit', ...options });
    proc.on('exit', (code) => (code ? reject(new Error(`Bun exited with code ${code}`)) : resolve()));
    proc.on('error', reject);
  });
}

interface PackageJson {
  main?: string;
  browser?: string;
  rollup?: {
    input?: string;
    output?: {
      name?: string;
    };
    external?: string[];
  };
}

// recursively get all files in a directory
function getAllFiles(dir: string, fileList: string[] = []): string[] {
  const files = fs.readdirSync(dir);
  files.forEach(file => {
    const filePath = path.join(dir, file);
    if (fs.statSync(filePath).isDirectory()) {
      getAllFiles(filePath, fileList);
    } else {
      fileList.push(filePath);
    }
  });
  return fileList;
}

// main program
async function main({ node, bundle }: ParsedArgs = argv): Promise<void> {
  // determine default options based on package.json values
  const pkg = JSON.parse(fs.readFileSync(path.join(cwd, 'package.json'), 'utf-8')) as PackageJson;
  const buildNode = node != null ? node : (!bundle && pkg.main !== pkg.browser);
  const buildBundle = bundle != null ? bundle : (!node && pkg.browser);

  if (buildNode) {
    console.log(colors.magenta('Building node modules with Bun...'));
    
    const srcDir = path.join(cwd, 'src');
    const distDir = path.join(cwd, 'dist');
    
    if (!fs.existsSync(srcDir)) {
      console.log(colors.yellow('No src directory found, skipping...'));
    } else {
      // Use Bun's transpiler to convert src to dist
      // Bun handles TypeScript natively and can output CommonJS
      const srcFiles = getAllFiles(srcDir).filter(f => f.endsWith('.ts') || f.endsWith('.js'));
      
      if (srcFiles.length === 0) {
        console.log(colors.yellow('No .ts or .js files found in src, skipping...'));
      } else {
        // Ensure dist directory exists
        if (!fs.existsSync(distDir)) {
          fs.mkdirSync(distDir, { recursive: true });
        }
        
        // Use Bun to transpile all TypeScript/JavaScript files to CommonJS
        // Build all source files at once using --outdir
        try {
          // Build all .ts and .js files from src to dist using outdir
          const entryPoints = srcFiles.filter(f => f.endsWith('.ts') || f.endsWith('.js'));
          
          if (entryPoints.length > 0) {
            await bunSpawn([
              'build',
              ...entryPoints,
              '--outdir', distDir,
              '--target', 'node',
              '--format', 'cjs',
              '--minify', 'false'
            ], { cwd });
          }
        } catch (err) {
          // Fallback: use tsc for transpilation if Bun build fails
          console.log(colors.yellow('Warning: Bun build failed, falling back to tsc for transpilation'));
          const tsconfigPath = path.join(cwd, 'tsconfig.json');
          if (fs.existsSync(tsconfigPath)) {
            try {
              await new Promise<void>((resolve, reject) => {
                const proc = spawn('tsc', ['--project', tsconfigPath, '--outDir', distDir], {
                  stdio: 'inherit',
                  cwd
                });
                proc.on('exit', (code) => (code ? reject(new Error(`tsc exited with code ${code}`)) : resolve()));
                proc.on('error', reject);
              });
            } catch (tscErr) {
              console.log(colors.yellow('Warning: tsc also failed, some files may not be transpiled'));
            }
          }
        }
        
        // Copy non-code files (yml, json, etc.)
        const allFiles = getAllFiles(srcDir);
        for (const file of allFiles) {
          if (!file.endsWith('.js') && !file.endsWith('.ts')) {
            const relPath = path.relative(srcDir, file);
            const distFile = path.join(distDir, relPath);
            const distDirPath = path.dirname(distFile);
            if (!fs.existsSync(distDirPath)) {
              fs.mkdirSync(distDirPath, { recursive: true });
            }
            fs.copyFileSync(file, distFile);
          }
        }
        
        // Generate TypeScript declaration files using tsc
        const tsconfigPath = path.join(cwd, 'tsconfig.json');
        if (fs.existsSync(tsconfigPath)) {
          try {
            await new Promise<void>((resolve, reject) => {
              const proc = spawn('tsc', ['--project', tsconfigPath, '--emitDeclarationOnly'], {
                stdio: 'inherit',
                cwd
              });
              proc.on('exit', (code) => (code ? reject(new Error(`tsc exited with code ${code}`)) : resolve()));
              proc.on('error', reject);
            });
            console.log(colors.green('✓ Type definitions generated'));
          } catch (err) {
            const error = err as Error;
            console.log(colors.yellow(`Warning: Could not generate type definitions: ${error.message}`));
          }
        }
        
        console.log(colors.green('✓ Node build complete'));
      }
    }
  }

  if (buildBundle) {
    if (buildNode) process.stdout.write('\n');
    console.log(colors.magenta('Building browser bundle with Bun...'));
    
    if (!pkg.browser) {
      console.log(colors.yellow('No browser field in package.json, skipping...'));
    } else {
      const inputFile = pkg.rollup?.input || (fs.existsSync(path.join(cwd, 'src/index.ts')) ? 'src/index.ts' : 'src/index.js');
      const outputFile = pkg.browser;
      const bundleName = pkg.rollup?.output?.name || pkg.name?.replace(/[^a-zA-Z0-9]/g, '') || 'bundle';
      
      // Bun build for browser bundle (IIFE format)
      const buildArgs = [
        'build',
        path.join(cwd, inputFile),
        '--outfile', path.join(cwd, outputFile),
        '--target', 'browser',
        '--format', 'iife',
        '--global-name', bundleName,
        '--minify', 'false'
      ];
      
      // Add external dependencies if specified
      if (pkg.rollup?.external) {
        for (const ext of pkg.rollup.external) {
          buildArgs.push('--external', ext);
        }
      }
      
      try {
        await bunSpawn(buildArgs, { cwd });
        console.log(colors.green(`✓ Browser bundle: ${inputFile} → ${outputFile}`));
      } catch (err) {
        const error = err as Error;
        console.error(colors.red('Bundle build failed:'), error.message);
        throw err;
      }
    }
  }
}

// handle errors
function handleError(err: Error & { exitCode?: number }): void {
  if (!err.exitCode) console.error(err);
  if (!argv.watch) process.exit(err.exitCode || 1);
}

// run everything and maybe watch for changes
main().catch(handleError).then(() => {
  if (argv.watch) {
    import('./watch.js').then(w => w.watch(() => main().catch(handleError))).catch(() => {
      console.error(colors.red('Watch mode not available: watch.js not found'));
      process.exit(1);
    });
  }
});

