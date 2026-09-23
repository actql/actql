import {performance} from 'node:perf_hooks';

const started = performance.now();
process.on('exit', () => {
  const usage = process.resourceUsage();
  process.stderr.write(`ACTQL_SEARCH_RESOURCE ${JSON.stringify({
    elapsedMs: performance.now() - started,
    maxRssKiB: usage.maxRSS,
    userCpuMicroseconds: usage.userCPUTime,
    systemCpuMicroseconds: usage.systemCPUTime,
  })}\n`);
});
