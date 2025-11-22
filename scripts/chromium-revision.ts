#!/usr/bin/env node

// This is deprecated as it is not working for 115

import url from 'url';
import path from 'path';

const SCRIPT_NAME = path.basename(url.fileURLToPath(import.meta.url));

// Usage/help output
if (!process.argv[2]) {
  // eslint-disable-next-line babel/no-unused-expressions
  (console.log(`\
Print a Chromium version's revision for each major platform

USAGE
  $ ${SCRIPT_NAME} VERSION

ARGUMENTS
  VERSION  A Chromium release version

EXAMPLE
 $ ${SCRIPT_NAME} 87.0.4280.88
`), process.exit());
}

// Required after usage for speedy help output
const { request } = await import('@percy/client/utils');
// eslint-disable-next-line import/no-extraneous-dependencies
const { default: logger } = await import('@percy/logger');
const log = logger('script');

// Chromium GitHub constants
const GH_API_URL = 'https://api.github.com/repos/chromium/chromium';
const GH_TAGS_URL = 'https://github.com/chromium/chromium/branch_commits';
const GH_HEADERS = {
  Accept: 'application/vnd.github.v3+json',
  // eslint-disable-next-line no-template-curly-in-string
  'User-Agent': `@percy/cli; ${SCRIPT_NAME}`
};

// Google Storage constants
const G_STORAGE_API_URL = 'https://www.googleapis.com/storage/v1/b/chromium-browser-snapshots/o';
const G_STORAGE_PREFIXES: Record<string, string> = {
  darwin: 'Mac',
  darwinArm: 'Mac_Arm',
  linux: 'Linux_x64',
  win64: 'Win_x64',
  win32: 'Win'
};

interface TaskState {
  i?: number;
  value?: unknown;
  authored?: boolean;
  platforms?: string[];
  range?: [number, number];
}

interface Tag {
  name: string;
  commit: {
    sha: string;
    url: string;
  };
}

interface Commit {
  sha: string;
  url: string;
  parents?: Array<{ url: string }>;
  author?: {
    name: string;
  };
  message?: string;
}

interface PlatformRevision {
  version: string;
  revision: number | string;
  sha: string;
}

// Runs a stateful async function repeatedly until it returns a truthy value while updating a log
// message with ellipses for each iteration of the task function
async function task<T>({ message, state: init, function: fn }: {
  message: (state: TaskState, dots: string) => string;
  state?: () => TaskState;
  function: (state: TaskState) => Promise<T | undefined>;
}): Promise<T> {
  return await (async function run(state: TaskState): Promise<T> {
    // log the message with an additional period for each iteration
    const i = state.i = (state.i || 0) + 1;
    log.progress(message(state, '.'.repeat(i)));

    // if the function does not return, run again
    const result = await fn(state);
    return result || run(state);
  })((init?.() || {}) as TaskState);
}

// The actual script that prints a revision corresponding to the provided version for each platform
async function printVersionRevisions(version: string): Promise<void> {
  // tags cannot be queried for by name with github's rest api; so query as many tags as we can
  // until a matching one is found
  const commit = await task<Commit>({
    message: (state, dots) => (state.value as Commit)?.sha
      ? `Tagged commit: ${(state.value as Commit).sha}`
      : `Searching for tagged version: ${version}${dots}`,
    async function(state) {
      if (state.value) return state.value as Commit;
      // this can be slow - the newer the browser, the less queries are needed
      const tags = await request(`${GH_API_URL}/tags?page=${state.i}&per_page=100`, { headers: GH_HEADERS }) as Tag[];
      const match = tags.find(tag => tag.name === version);
      state.value = match?.commit;
      return state.value as Commit | undefined;
    }
  });

  // a bot likely published the release, so find the first human-authored commit
  const authored = await task<Commit>({
    state: () => ({ value: commit }),
    message: (state, dots) => state.authored
      ? `Authored commit: ${(state.value as Commit).sha}`
      : `Fetching authored commit${dots}`,
    async function(state) {
      // get each parent commit until the authored commit is found
      if (state.authored) return state.value as Commit;
      const commitData = await request((state.value as Commit).url, { headers: GH_HEADERS }) as Commit;
      const { parents } = commitData;
      if (!parents || parents.length === 0) {
        state.value = commitData;
        state.authored = true;
        return state.value as Commit;
      }
      const parent = await request(parents[0].url, { headers: GH_HEADERS }) as Commit;
      state.value = parent.commit ? parent.commit : parent;
      // an author name ending in "-bot" is likely an automated commit
      state.authored = !(state.value as Commit).author?.name.endsWith('-bot');
      return state.authored ? state.value as Commit : undefined;
    }
  });

  // parse the authored commit's message for the revision number; relies on the message format
  // ending in "refs/head/main@{000000}" where zeros are the revision number
  const revisionMatch = authored.message?.match(/refs\/heads\/main@\{#(\d+)}$/);
  if (!revisionMatch) {
    throw new Error('Could not parse revision from commit message');
  }
  const revision = parseInt(revisionMatch[1], 10);
  log.info(`Commit position: ${revision}`);

  // for each platform, find the first suitable revision matching the desired version spanning back
  // 50 revisions (not all platforms release at the same time)
  const revisions = await task<Record<string, PlatformRevision>>({
    state: () => ({
      platforms: ['linux', 'win64', 'win32', 'darwin', 'darwinArm'],
      range: [revision - 50, revision],
      value: {}
    }),
    message: (state, dots) => (state.i || 0) <= (state.platforms?.length || 0)
      ? `Determining platform revisions: ${state.platforms?.[(state.i || 0) - 1]}${dots}`
      : 'Matching revisions:',
    async function(state) {
      const platform = state.platforms?.[(state.i || 0) - 1];
      if (!platform) return state.value as Record<string, PlatformRevision>;
      let rev = state.range?.[1] || revision;

      for (; rev >= (state.range?.[0] || revision - 50); rev--) {
        // query google's storage api for the platform revision
        const response = await request((
          `${G_STORAGE_API_URL}?fields=items(name,metadata)&` +
            `prefix=${G_STORAGE_PREFIXES[platform]}/${rev}`
        ), {}) as { items?: Array<{ metadata?: { 'cr-git-commit'?: string } }> };

        // no matching revision for this platform
        if (!response.items) continue;
        // check if the revision's commit is included in the desired release version
        const sha = response.items[0]?.metadata?.['cr-git-commit'];
        if (!sha) continue;
        const tagsPage = await request(`${GH_TAGS_URL}/${sha}`, {}) as string;
        const tagMatches = tagsPage.match(/\/releases\/tag\/[\d.]+/g);
        if (!tagMatches) continue;
        const tags = tagMatches.map(t => t.replace('/releases/tag/', ''));

        // no matching version for this revision
        if (!tags.includes(version)) continue;

        // found a suitable revision for this platform
        (state.value as Record<string, PlatformRevision>)[platform] = {
          version: tags[tags.length - 1],
          revision: rev,
          sha
        };

        break;
      }

      // no suitable revision was found for this platform
      if (!(state.value as Record<string, PlatformRevision>)[platform]) {
        (state.value as Record<string, PlatformRevision>)[platform] = {
          revision: '-'.repeat(String(rev).length),
          version: 'no match',
          sha: 'none'
        };
      }
      return undefined; // Continue to next platform
    }
  });

  // log all matching revisions
  logger.stdout.write('\n' + (
    Object.entries(revisions).map(([platform, i]) => (
      `${platform}: ${i.revision} (${i.sha}; ${i.version})`
    )).join('\n') + '\n\n'));
}

// call the script with the first provided arg
printVersionRevisions(process.argv[2]).catch(error => {
  // request errors have a response body
  const err = error as { response?: { body?: { message?: string } } };
  log.error(err.response?.body?.message || error);
});

