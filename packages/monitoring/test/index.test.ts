import Monitoring from '../src/index.js';
import si from 'systeminformation';
import os from 'os';
import logger from '@percy/logger/test/helpers';
import { promises as fs } from 'fs';
import { vi, expect } from 'vitest';

describe('Monitoring', () => {
  let monitoring, mockExecuteMonitoring;
  let platform = 'test_platform';

  beforeEach(async () => {
    vi.spyOn(os, 'platform').mockReturnValue(platform);
    monitoring = new Monitoring();
    logger.loglevel('debug');
    process.env.PERCY_LOGLEVEL = 'debug';
    await logger.mock({ isTTY: true, level: 'debug' });
  });

  afterEach(() => {
    delete process.env.PERCY_LOGLEVEL;
  });

  describe('startMonitoring', () => {
    beforeEach(() => {
      vi.useFakeTimers();
      mockExecuteMonitoring = vi.spyOn(monitoring, 'executeMonitoring').mockResolvedValue(undefined);
    });

    afterEach(() => {
      vi.useRealTimers();
    });

    it('calls executeMonitoring after some interval', async () => {
      await monitoring.startMonitoring();
      expect(mockExecuteMonitoring.mock.calls.length).toEqual(1);
      vi.advanceTimersByTime(5002);
      expect(mockExecuteMonitoring.mock.calls.length).toEqual(2);
      expect(logger.stderr).toEqual(
        expect.arrayContaining([
          '[percy:monitoring] Started monitoring system metrics'
        ])
      );
    });

    it('early returns if monitoring is already active', async () => {
      await monitoring.startMonitoring();
      expect(mockExecuteMonitoring.mock.calls.length).toEqual(1);
      vi.advanceTimersByTime(1000);
      await monitoring.startMonitoring();
      expect(mockExecuteMonitoring.mock.calls.length).toEqual(1);
    });
  });

  describe('getPercyEnv', () => {
    beforeEach(() => {
      process.env.PERCY_SKIP_UPDATE_CHECK = 'false';
      process.env.PERCY_TOKEN = '<web-token>';
      process.env.MY_RUBY_HOME = 'test_path';
    });

    afterEach(() => {
      delete process.env.PERCY_SKIP_UPDATE_CHECK;
      delete process.env.PERCY_TOKEN;
      delete process.env.MY_RUBY_HOME;
    });

    it('return percy envs keys', async () => {
      const keys = monitoring.getPercyEnv();
      expect(keys.PERCY_SKIP_UPDATE_CHECK).toEqual('false');
      expect(keys.PERCY_TOKEN).toEqual(undefined);
      expect(keys.MY_RUBY_HOME).toEqual(undefined);
    });
  });

  describe('logSystemInfo', () => {
    beforeEach(() => {
      vi.spyOn(fs, 'readFile').mockRejectedValue(new Error('File not exists'));
      vi.spyOn(si, 'mem').mockResolvedValue({ total: 10344343324, swaptotal: 245343444244 });
      vi.spyOn(os, 'arch').mockReturnValue('test_arch');
      vi.spyOn(os, 'type').mockReturnValue('test_type');
      vi.spyOn(os, 'release').mockReturnValue('test_release');
      vi.spyOn(si, 'cpu').mockResolvedValue({ cores: 3 });
      vi.spyOn(os, 'cpus').mockReturnValue([{ model: 'Test CPU Model' }]);
    });

    it('logs os, cpu, memory info', async () => {
      const getDiskSpaceInfoMock = vi.fn().mockResolvedValue('123.45 gb');
      await monitoring.logSystemInfo({ getDiskSpaceInfo: getDiskSpaceInfoMock });
      expect(logger.stderr).toEqual(expect.arrayContaining([
        '[percy:monitoring] [Operating System] Platform: test_platform, Type: test_type, Release: test_release',
        '[percy:monitoring] [CPU] Name: Test CPU Model',
        '[percy:monitoring] [CPU] Arch: test_arch, cores: 3',
        '[percy:monitoring] [Disk] Available Space: 123.45 gb',
        '[percy:monitoring] [Memory] Total: 9.633920457214117 gb, Swap Space: 228.49388815835118 gb',
        '[percy:monitoring] Container Level: false, Pod Level: false, Machine Level: true'
      ]));
    });

    it('logs error when unexpected error occurred', async () => {
      vi.spyOn(os, 'arch').mockImplementation(() => { throw new Error('err'); });
      await monitoring.logSystemInfo();
      expect(logger.stderr).toEqual(expect.arrayContaining([
        '[percy:monitoring] Error logging system info: Error: err'
      ]));
    });

    it('logs error when getClientCPUDetails fails', async () => {
      const getClientCPUDetailsMock = vi.fn().mockImplementation(() => { throw new Error('Test Error'); });
      await monitoring.logSystemInfo({ getClientCPUDetails: getClientCPUDetailsMock });
      expect(logger.stderr).toEqual(expect.arrayContaining([
        '[percy:monitoring] Error logging system info: Error: Test Error'
      ]));
    });
  });

  describe('executeMonitoring', () => {
    let mockCpuUsage, mockMemUsage;

    beforeEach(() => {
      mockCpuUsage = vi.spyOn(monitoring, 'monitoringCPUUsage').mockResolvedValue(undefined);
      mockMemUsage = vi.spyOn(monitoring, 'monitorMemoryUsage').mockResolvedValue(undefined);
    });
    it('calls monitoringCPUUsage and monitoringMemoryUsage and update lastExecutedAt', async () => {
      monitoring.lastExecutedAt = null;
      monitoring.running = false;
      await monitoring.executeMonitoring();

      expect(monitoring.running).toEqual(true);
      expect(mockMemUsage).toHaveBeenCalledTimes(1);
      expect(mockCpuUsage).toHaveBeenCalledTimes(1);
      expect(monitoring.lastExecutedAt).not.toEqual(null);
    });
  });

  describe('monitoringCPUUsage', () => {
    it('updates cpu info details', async () => {
      monitoring.cpuInfo = null;
      await monitoring.monitoringCPUUsage('win32');
      expect(monitoring.cpuInfo).not.toEqual(null);
      expect(monitoring.cpuInfo.currentUsagePercent).not.toEqual(null);
    });
  });

  describe('monitoringMemoryUsage', () => {
    it('updates memory usage details', async () => {
      monitoring.memoryUsageInfo = null;
      await monitoring.monitorMemoryUsage('win32');
      expect(monitoring.memoryUsageInfo).not.toEqual(null);

      // not mocking os and si module, therefore only checking if values
      // are getting updated or not
      expect(monitoring.memoryUsageInfo.currentUsagePercent).not.toEqual(null);
    });
  });

  describe('getMonitoringInfo', () => {
    let mockCpuUsage = { currentUsagePercent: 3.4, cores: 4 };
    let mockMemoryUsage = { currentUsagePercent: 12.3, totalMemory: 122 };
    it('returns current cpu and memory usage %', async () => {
      monitoring.cpuInfo = mockCpuUsage;
      monitoring.memoryUsageInfo = mockMemoryUsage;
      expect(monitoring.getMonitoringInfo()).toEqual({
        cpuInfo: mockCpuUsage,
        memoryUsageInfo: mockMemoryUsage
      });
    });
  });

  describe('stopMonitoring', () => {
    let mockClearInterval;
    beforeEach(() => {
      mockClearInterval = vi.spyOn(global, 'clearInterval').mockReturnValue(undefined);
    });

    it('clear setInterval and reset all monitoring values', async () => {
      await monitoring.startMonitoring();
      expect(monitoring.running).toEqual(true);
      expect(monitoring.lastExecutedAt).not.toEqual(null);
      expect(monitoring.cpuInfo).not.toEqual({});
      expect(monitoring.monitoringId).not.toEqual(null);

      monitoring.stopMonitoring();

      expect(monitoring.running).toEqual(false);
      expect(monitoring.lastExecutedAt).toEqual(null);
      expect(monitoring.cpuInfo).toEqual({});
      expect(monitoring.monitoringId).toEqual(null);
    });

    it('does nothing when no monitoring is enabled', async () => {
      await monitoring.startMonitoring();
      monitoring.stopMonitoring();
      expect(mockClearInterval).toHaveBeenCalledTimes(1);

      mockClearInterval.mockClear();
      monitoring.stopMonitoring();
      expect(mockClearInterval).not.toHaveBeenCalled();
    });
  });
});
