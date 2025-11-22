import helpers from './helpers.js';
import utils from '@percy/sdk-utils';
import { vi, expect } from 'vitest';

describe('SDK Utils', () => {
  beforeEach(async () => {
    await helpers.setupTest();
  });

  describe('percy', () => {
    let { percy } = utils;

    it('contains the server address as defined by PERCY_SERVER_ADDRESS', () => {
      expect(percy.address).toEqual('http://localhost:5338');
      process.env.PERCY_SERVER_ADDRESS = 'http://localhost:1234';
      expect(percy.address).toEqual('http://localhost:1234');
    });

    it('sets PERCY_SERVER_ADDRESS when setting percy.address', () => {
      expect(percy.address).toEqual('http://localhost:5338');
      percy.address = 'http://localhost:4567';
      expect(percy.address).toEqual('http://localhost:4567');
      expect(process.env.PERCY_SERVER_ADDRESS).toEqual('http://localhost:4567');
    });

    it('contains placeholder percy server version information', () => {
      expect(percy.version.toString()).toEqual('0.0.0');
      expect(percy.version).toHaveProperty('major', 0);
      expect(percy.version).toHaveProperty('minor', 0);
      expect(percy.version).toHaveProperty('patch', 0);
      expect(percy.version).not.toHaveProperty('prerelease');
      expect(percy.version).not.toHaveProperty('build');
    });

    describe('after calling isPercyEnabled()', () => {
      let { isPercyEnabled } = utils;

      beforeEach(async () => {
        await helpers.test('version', '1.2.3-beta.4');
        await helpers.test('build-created');
        await expect(isPercyEnabled()).resolves.toBe(true);
      });

      it('contains updated percy server version information', () => {
        expect(percy.version.toString()).toEqual('1.2.3-beta.4');
        expect(percy.version).toHaveProperty('major', 1);
        expect(percy.version).toHaveProperty('minor', 2);
        expect(percy.version).toHaveProperty('patch', 3);
        expect(percy.version).toHaveProperty('prerelease', 'beta');
        expect(percy.version).toHaveProperty('build', 4);
      });

      it('contains percy config', () => {
        expect(percy).toHaveProperty('config.snapshot.widths', [375, 1280]);
      });

      it('contains type', () => {
        expect(percy.type).toEqual('web');
      });

      it('contains percy build info', () => {
        expect(percy.build).toHaveProperty('id', '123');
        expect(percy.build).toHaveProperty('url', 'https://percy.io/test/test/123');
      });

      it('contains percy width', () => {
        expect(percy.widths).toHaveProperty('config', [375, 1280]);
        expect(percy.widths).toHaveProperty('mobile', []);
      });
    });
  });

  describe('isPercyEnabled()', () => {
    let { isPercyEnabled } = utils;

    it('calls the healthcheck endpoint and caches the result', async () => {
      await expect(isPercyEnabled()).resolves.toBe(true);
      await expect(isPercyEnabled()).resolves.toBe(true);
      await expect(isPercyEnabled()).resolves.toBe(true);

      // no matter how many calls, we should only have one healthcheck request
      await expect(helpers.get('requests', r => r.url))
        .resolves.toEqual(['/percy/healthcheck']);
    });

    it('disables snapshots when the healthcheck fails', async () => {
      await helpers.test('error', '/percy/healthcheck');
      await expect(isPercyEnabled()).resolves.toBe(false);

      expect(helpers.logger.stdout).toEqual(expect.arrayContaining([
        '[percy] Percy is not running, disabling snapshots'
      ]));
    });

    it('disables snapshots when the request errors', async () => {
      await helpers.test('disconnect', '/percy/healthcheck');
      await expect(isPercyEnabled()).resolves.toBe(false);

      expect(helpers.logger.stdout).toEqual(expect.arrayContaining([
        '[percy] Percy is not running, disabling snapshots'
      ]));
    });

    it('disables snapshots when the API version is unsupported', async () => {
      await helpers.test('version', '0.1.0');
      await expect(isPercyEnabled()).resolves.toBe(false);

      expect(helpers.logger.stdout).toEqual(expect.arrayContaining([
        '[percy] Unsupported Percy CLI version, disabling snapshots'
      ]));
    });

    it('returns false if the build fails during a snapshot', async () => {
      await helpers.test('error', '/percy/snapshot');
      await helpers.test('build-failure');

      await expectAsync(isPercyEnabled()).toBeResolvedTo(true);
      await expect(utils.postSnapshot({})).resolves.toBeDefined();
      await expect(isPercyEnabled()).resolves.toBe(false);
    });
  });

  describe('waitForPercyIdle()', () => {
    let { waitForPercyIdle } = utils;

    it('gets idle state from the CLI API idle endpoint', async () => {
      await expect(waitForPercyIdle()).resolves.toBe(true);
      await expect(helpers.get('requests', r => r.url))
        .resolves.toEqual(['/percy/idle']);
    });

    it('polls the CLI API idle endpoint on timeout', async () => {
      vi.spyOn(utils.request, 'fetch').mockImplementation((...args) => {
        return utils.request.fetch.mock.calls.length > 2
          ? utils.request.fetch.originalImplementation?.(...args)
        // eslint-disable-next-line prefer-promise-reject-errors
          : Promise.reject({ code: 'ETIMEDOUT' });
      });

      await expect(waitForPercyIdle()).resolves.toBe(true);
      expect(utils.request.fetch).toHaveBeenCalledTimes(3);
    });
  });

  describe('fetchPercyDOM()', () => {
    let { fetchPercyDOM } = utils;

    it('fetches @percy/dom from the CLI API and caches the result', async () => {
      let domScript = expect.stringMatching(/\b(PercyDOM)\b/);
      await expect(fetchPercyDOM()).resolves.toEqual(domScript);
      await expect(fetchPercyDOM()).resolves.toEqual(domScript);
      await expect(helpers.get('requests', r => r.url))
        .resolves.toEqual(['/percy/dom.js']);
    });
  });

  describe('postSnapshot(options[, params])', () => {
    let { postSnapshot } = utils;
    let options;

    beforeEach(() => {
      options = {
        name: 'Snapshot Name',
        url: 'http://localhost:8000/',
        domSnapshot: '<SERIALIZED_DOM>',
        clientInfo: 'sdk/version',
        environmentInfo: ['lib/version', 'lang/version'],
        enableJavaScript: true
      };
    });

    it('posts snapshot options to the CLI API snapshot endpoint', async () => {
      await expect(postSnapshot(options)).resolves.toEqual(expect.objectContaining({ body: { success: true } }));
      await expect(helpers.get('requests')).resolves.toEqual([{
        url: '/percy/snapshot',
        method: 'POST',
        body: options
      }]);
    });

    it('throws when the snapshot API fails', async () => {
      await helpers.test('error', '/percy/snapshot');

      await expect(postSnapshot({}))
        .rejects.toThrow('testing');
    });

    it('disables snapshots when a build fails', async () => {
      await helpers.test('error', '/percy/snapshot');
      await helpers.test('build-failure');
      utils.percy.enabled = true;

      expect(utils.percy.enabled).toEqual(true);
      await expect(postSnapshot({})).resolves.toBeDefined();
      expect(utils.percy.enabled).toEqual(false);
    });

    it('accepts URL parameters as the second argument', async () => {
      let params = { test: 'foobar' };

      await expect(postSnapshot(options, params)).resolves.toBeDefined();
      await expect(helpers.get('requests')).resolves.toEqual([{
        url: `/percy/snapshot?${new URLSearchParams(params)}`,
        method: 'POST',
        body: options
      }]);
    });
  });

  describe('captureAutomateScreenshot(options[, params])', () => {
    let { captureAutomateScreenshot } = utils;
    let options;

    beforeEach(() => {
      options = {
        snapshotName: 'Snapshot Name',
        commandExecutorUrl: 'http://localhost:8000/',
        capabilities: '<SERIALIZED_capabilities>',
        sessionCapabilites: '<SERIALIZED_capabilities>',
        clientInfo: 'sdk/version',
        environmentInfo: ['lib/version', 'lang/version'],
        sessionId: '123'
      };
      vi.spyOn(utils.request, 'post').mockResolvedValue(true);
    });

    it('posts screenshot options to the CLI API snapshot endpoint', async () => {
      await captureAutomateScreenshot(options);
      expect(utils.request.post).toHaveBeenCalledWith('/percy/automateScreenshot', options);
    });

    it('posts screenshot options to the CLI API snapshot endpoint and return data', async () => {
      vi.spyOn(utils.request, 'post').mockResolvedValue({ data: 'sync-data' });
      const response = await captureAutomateScreenshot(options);
      expect(response).toEqual({ data: 'sync-data' });
      expect(utils.request.post).toHaveBeenCalledWith('/percy/automateScreenshot', options);
    });

    it('throws when the screenshot API fails', async () => {
      vi.spyOn(utils.request, 'post').mockRejectedValue(new Error('testing'));
      await expect(captureAutomateScreenshot({}))
        .rejects.toThrow('testing');
    });

    it('disables screenshots when a build fails', async () => {
      // eslint-disable-next-line prefer-promise-reject-errors
      vi.spyOn(utils.request, 'post').mockRejectedValue({ response: { body: { build: { error: true } } } });

      utils.percy.enabled = true;
      expect(utils.percy.enabled).toEqual(true);
      await captureAutomateScreenshot({});
      expect(utils.percy.enabled).toEqual(false);
    });

    it('accepts URL parameters as the second argument', async () => {
      let params = { test: 'foobar' };

      await expect(captureAutomateScreenshot(options, params)).resolves.toBeDefined();
      expect(utils.request.post).toHaveBeenCalledWith(`/percy/automateScreenshot?${new URLSearchParams(params)}`, options);
    });
  });

  describe('postComparison(options[, params])', () => {
    let { postComparison } = utils;
    let options;

    beforeEach(() => {
      options = {
        name: 'Snapshot Name',
        tag: { name: 'Tag Name' },
        tiles: [{ filename: '/foo/bar' }],
        externalDebugUrl: 'http://external-debug-url'
      };
    });

    it('posts comparison options to the CLI API comparison endpoint', async () => {
      await expect(postComparison(options)).resolves.toBeDefined();
      await expect(helpers.get('requests')).resolves.toEqual([{
        url: '/percy/comparison',
        method: 'POST',
        body: options
      }]);
    });

    it('throws when the comparison API fails', async () => {
      await helpers.test('error', '/percy/comparison');

      await expect(postComparison({}))
        .rejects.toThrow('testing');
    });

    it('disables snapshots when a build fails', async () => {
      await helpers.test('error', '/percy/comparison');
      await helpers.test('build-failure');
      utils.percy.enabled = true;

      expect(utils.percy.enabled).toEqual(true);
      await expect(postComparison({})).resolves.toBeDefined();
      expect(utils.percy.enabled).toEqual(false);
    });

    it('accepts URL parameters as the second argument', async () => {
      let params = { test: 'foobar' };

      await expect(postComparison(options, params)).resolves.toBeDefined();
      await expect(helpers.get('requests')).resolves.toEqual([{
        url: `/percy/comparison?${new URLSearchParams(params)}`,
        method: 'POST',
        body: options
      }]);
    });
  });

  describe('postBuildEvents(options)', () => {
    let { postBuildEvents } = utils;
    let options;

    beforeEach(() => {
      options = {
        errorMessage: 'someError',
        errorKind: 'sdk',
        cliVersion: '1.2.3'
      };
    });

    it('posts comparison options to the CLI API event endpoint', async () => {
      vi.spyOn(utils.request, 'post').mockResolvedValue(undefined);
      await expect(postBuildEvents(options)).resolves.toBeDefined();
      await expect(helpers.get('requests')).resolves.toEqual({});
    });

    it('throws when the event API fails', async () => {
      await helpers.test('error', '/percy/events');

      await expect(postBuildEvents({}))
        .rejects.toThrow('testing');
    });
  });

  describe('flushSnapshots([options])', () => {
    let { flushSnapshots } = utils;

    it('does nothing when percy is not enabled', async () => {
      await expect(flushSnapshots()).resolves.toBeDefined();
      await expect(helpers.get('requests')).resolves.toEqual({});
    });

    it('posts options to the CLI API flush endpoint', async () => {
      utils.percy.enabled = true;

      await expectAsync(flushSnapshots()).toBeResolved();
      await expect(flushSnapshots({ name: 'foo' })).resolves.toBeDefined();
      await expect(flushSnapshots(['bar', 'baz'])).resolves.toBeDefined();

      await expect(helpers.get('requests')).resolves.toEqual([
        { url: '/percy/flush', method: 'POST' },
        { url: '/percy/flush', method: 'POST', body: [{ name: 'foo' }] },
        { url: '/percy/flush', method: 'POST', body: [{ name: 'bar' }, { name: 'baz' }] }
      ]);
    });
  });

  describe('logger()', () => {
    let browser = process.env.__PERCY_BROWSERIFIED__;
    let log, err, stdout, stderr;
    let { logger } = utils;

    let ANSI_REG = new RegExp('[\\u001B\\u009B][[\\]()#;?]*(' + (
      '(?:(?:[a-zA-Z\\d]*(?:;[-a-zA-Z\\d\\/#&.:=?%@~_]*)*)?\\u0007)|' +
      '(?:(?:\\d{1,4}(?:;\\d{0,4})*)?[\\dA-PR-TZcf-ntqry=><~]))'
    ), 'g');

    let captureLogs = acc => msg => {
      msg = msg.replace(/\r\n/g, '\n');
      msg = msg.replace(ANSI_REG, '');
      acc.push(msg.replace(/\n$/, ''));
    };

    beforeEach(async () => {
      await helpers.setupTest({ logger: false });
      err = new Error('Test error');
      err.stack = 'Error stack';
      log = utils.logger('test');
      stdout = [];
      stderr = [];

      if (browser) {
        vi.spyOn(console, 'log').mockImplementation(captureLogs(stdout));
        vi.spyOn(console, 'warn').mockImplementation(captureLogs(stderr));
        vi.spyOn(console, 'error').mockImplementation(captureLogs(stderr));
      } else {
        vi.spyOn(process.stdout, 'write').mockImplementation(captureLogs(stdout));
        vi.spyOn(process.stderr, 'write').mockImplementation(captureLogs(stderr));
      }
    });

    it('creates a minimal percy logger', async () => {
      log.info('Test info');
      log.warn('Test warn');
      log.error('Test error');
      log.error({ toString: () => 'Test error object' });
      log.error(err);

      // not logged because loglevel is not debug
      log.debug('Test debug');

      expect(stdout).toEqual([
        '[percy] Test info'
      ]);
      expect(stderr).toEqual([
        '[percy] Test warn',
        '[percy] Test error',
        '[percy] Test error object',
        '[percy] Error: Test error'
      ]);
    });

    it('logs the namespace when loglevel is debug', async () => {
      logger.loglevel('debug');

      log.info('Test debug info');
      log.debug('Test debug log');
      log.debug({ stack: 'Error like' });
      log.error(err);

      expect(stdout).toEqual([
        '[percy:test] Test debug info',
        // browser debug logs use console.log
        ...(browser ? [
          '[percy:test] Test debug log',
          '[percy:test] Error like'
        ] : [])
      ]);
      expect(stderr).toEqual([
        // node debug logs write to stderr
        ...(!browser ? [
          '[percy:test] Test debug log',
          '[percy:test] Error like'
        ] : []),
        '[percy:test] Error stack'
      ]);
    });

    it('sends logs to cli if log level is error', async () => {
      // we never want to await in real sdk but we await in test for validation
      await log.error('Some error', { name: 'abcd' });

      await expect(helpers.get('requests')).resolves.toEqual([{
        url: '/percy/log',
        method: 'POST',
        body: {
          level: 'error',
          message: expect.stringContaining('Some error'),
          meta: { name: 'abcd' }
        }
      }]);
    });

    it('sends all logs to cli if log level is debug', async () => {
      logger.loglevel('debug');
      // we never want to await in real sdk but we await in test for validation
      await log.error('Some error', { name: 'abcd' });
      await log.info('Some info', { name: 'abcd' });

      await expect(helpers.get('requests')).resolves.toEqual([{
        url: '/percy/log',
        method: 'POST',
        body: {
          level: 'error',
          message: expect.stringContaining('Some error'),
          meta: { name: 'abcd' }
        }
      }, {
        url: '/percy/log',
        method: 'POST',
        body: {
          level: 'info',
          message: jasmine.stringContaining('Some info'),
          meta: { name: 'abcd' }
        }
      }]);
    });

    it('sends logs error if sending to cli fails', async () => {
      await helpers.test('error', '/percy/log');
      // we never want to await in real sdk but we await in test for validation
      await log.error('Some error', { name: 'abcd' });

      expect(stderr).toEqual([
        '[percy] Some error',
        '[percy] Could not send logs to cli'
      ]);
    });
  });
});
