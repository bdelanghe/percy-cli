import fs from 'fs';
import url from 'url';
import path from 'path';

const ROOT = path.resolve(url.fileURLToPath(import.meta.url), '../..');
const CJS_REG = /(^|\n)(module\.)?(exports)/;
const MOCK_REG = /^mock:\/\/|\?.+$/g;

// Extend global type for mock imports
declare global {
  // eslint-disable-next-line no-var
  var __MOCK_IMPORTS__: Map<string, { __uid__: number } & Record<string, unknown>>;
}

// Extend fs type for $vol property
interface FSWithVol extends typeof fs {
  $vol?: {
    existsSync: (path: string) => boolean;
    readFileSync: (path: string) => string | Buffer;
  };
}

// global mocks can be added from tests
export const MOCK_IMPORTS = global.__MOCK_IMPORTS__ = global.__MOCK_IMPORTS__ ||
  new Proxy(Object.assign(new Map<string, { __uid__: number } & Record<string, unknown>>(), { __uid__: 0 }), {
    get(target, prop, receiver) {
      if (typeof target[prop as keyof typeof target] !== 'function') return target[prop as keyof typeof target];

      return prop === 'set' ? (key: string, value: unknown) => {
        return (target as Map<string, unknown>).set(key, (target.__uid__++, value));
      } : (prop === 'get' || prop === 'has') ? (key: string) => {
        return (target as Map<string, unknown>)[prop as 'get' | 'has'](key.replace(MOCK_REG, ''));
      } : (target[prop as keyof typeof target] as Function).bind(target);
    }
  }) as typeof global.__MOCK_IMPORTS__;

// matches and rewrites internal imports into absolute src paths
export const LOADER_ALIAS = {
  find: /^@percy\/([^/]+)(?:\/(.+))?$|(^[./]+?)\/dist\/(.+\.(js|ts))$/,
  replace: (specifier: string, name?: string, subpath?: string, rel?: string, filename?: string): string => {
    if (rel) {
      // Change .js to .ts in src path if it's a dist import
      const srcFile = filename?.replace(/\.js$/, '.ts') ?? '';
      return `${rel}/src/${srcFile}`;
    }
    if (!subpath) return path.resolve(ROOT, `./packages/${name}/src/index.ts`);
    const pkg = JSON.parse(fs.readFileSync(path.join(ROOT, `./packages/${name}/package.json`), 'utf-8')) as {
      exports?: Record<string, string>;
    };
    let alias = pkg.exports?.[`./${subpath}`]?.replace('./dist', './src');
    if (alias) {
      // Change .js to .ts in the alias path
      alias = alias.replace(/\.js$/, '.ts');
      return path.resolve(ROOT, `./packages/${name}/${alias}`);
    }
    return specifier;
  }
};

interface ResolveContext {
  parentURL?: string;
}

interface ResolveResult {
  url: string;
}

type DefaultResolve = (specifier: string, context: ResolveContext, defaultResolve: DefaultResolve) => Promise<ResolveResult>;

// resolve specifier file url
export async function resolve(specifier: string, context: ResolveContext, defaultResolve: DefaultResolve): Promise<ResolveResult> {
  // check for import or filesystem mocks
  if (MOCK_IMPORTS.has(specifier)) {
    return { url: `mock://${specifier}?__mock__=${MOCK_IMPORTS.__uid__}&module` };
  } else if (context.parentURL && '$vol' in fs) {
    const filename = specifier.startsWith('file:') ? url.fileURLToPath(specifier) : specifier;
    const filepath = path.resolve(path.dirname(url.fileURLToPath(context.parentURL)), filename);
    const fsWithVol = fs as FSWithVol;

    if (fsWithVol.$vol?.existsSync(filepath)) {
      const content = fsWithVol.$vol.readFileSync(filepath);
      const fmt = CJS_REG.test(content.toString()) ? 'commonjs' : 'module';
      return { url: `${url.pathToFileURL(filepath)}?__mock__=${MOCK_IMPORTS.__uid__}&${fmt}` };
    }
  }

  // rewrite dist to src in development
  if (specifier.startsWith('#')) {
    const pkgRoot = url.fileURLToPath(context.parentURL!.replace(/(packages\/[^/]+\/).+$/, '$1'));
    const pkgJSON = JSON.parse(fs.readFileSync(path.resolve(pkgRoot, 'package.json'), 'utf-8')) as {
      imports?: Record<string, { node?: string }>;
    };
    let alias = pkgJSON.imports?.[specifier]?.node?.replace('./dist', './src');
    if (alias) {
      // Change .js to .ts in the alias path
      alias = alias.replace(/\.js$/, '.ts');
      specifier = path.resolve(pkgRoot, alias);
    }
  } else {
    specifier = specifier.replace(LOADER_ALIAS.find, LOADER_ALIAS.replace);
  }

  // transform absolute filepaths into absolute file urls
  if (specifier.startsWith(ROOT)) specifier = url.pathToFileURL(specifier).href;

  // use default resolve when not mocked
  return defaultResolve(specifier, context, defaultResolve);
}

interface GetFormatContext {
  parentURL?: string;
}

interface FormatResult {
  format: string;
}

type DefaultGetFormat = (srcURL: string, context: GetFormatContext, defaultGetFormat: DefaultGetFormat) => Promise<FormatResult>;

// get module format for loader mocks
export async function getFormat(srcURL: string, context: GetFormatContext, defaultGetFormat: DefaultGetFormat): Promise<FormatResult> {
  return srcURL.includes('?__mock__')
    ? { format: srcURL.split('?')[1].split('&')[1] }
    : defaultGetFormat(srcURL, context, defaultGetFormat);
}

// generate mock sources for mocked modules
function mockSource(mockURL: string): string {
  if (MOCK_IMPORTS.has(mockURL)) {
    const key = `global.__MOCK_IMPORTS__.get("${mockURL}")`;
    const mockValue = MOCK_IMPORTS.get(mockURL);

    return Object.keys(mockValue || {}).reduce((src, name) => src + (
      `export ${name === 'default' ? name : `const ${name} =`} ${key}.${name};\n`
    ), '');
  } else {
    const fsWithVol = fs as FSWithVol;
    return fsWithVol.$vol?.readFileSync(url.fileURLToPath(mockURL)).toString() ?? '';
  }
}

interface GetSourceContext {
  parentURL?: string;
}

interface SourceResult {
  source: string;
}

type DefaultGetSource = (srcURL: string, context: GetSourceContext, defaultGetSource: DefaultGetSource) => Promise<SourceResult>;

// return loader mocks as module sources
export async function getSource(srcURL: string, context: GetSourceContext, defaultGetSource: DefaultGetSource): Promise<SourceResult> {
  if (srcURL.includes('?__mock__')) return { source: mockSource(srcURL) };
  return defaultGetSource(srcURL, context, defaultGetSource);
}

interface TransformSourceContext {
  parentURL?: string;
}

interface TransformResult {
  source: string;
}

type DefaultTransformSource = (source: string | Buffer, context: TransformSourceContext, defaultTransformSource: DefaultTransformSource) => Promise<TransformResult>;

// return loader mocks or pass through sources (Bun handles ES modules natively)
export async function transformSource(source: string | Buffer, context: TransformSourceContext, defaultTransformSource: DefaultTransformSource): Promise<TransformResult> {
  // Bun can run ES modules natively, so no transformation needed
  // Just pass through to default handler
  return defaultTransformSource(source, context, defaultTransformSource);
}

