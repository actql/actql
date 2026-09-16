// Diagnostic sampling only: observed peaks are lower bounds, not memory limits.
// Store a constant-size aggregate, never a timeline that grows with the workload.
const fields = ['rss', 'heapTotal', 'heapUsed', 'external', 'arrayBuffers'];

export function sampleControllerMemory({intervalMs = 20, read = () => process.memoryUsage()} = {}) {
  if (!Number.isSafeInteger(intervalMs) || intervalMs < 1 || intervalMs > 1000 || typeof read !== 'function') {
    throw new TypeError('InvalidMemorySamplingConfiguration');
  }
  const snapshot = () => {
    const value = read();
    return Object.freeze(Object.fromEntries(fields.map(field => {
      const bytes = value?.[field];
      if (!Number.isSafeInteger(bytes) || bytes < 0) throw new TypeError('InvalidMemorySample');
      return [field, bytes];
    })));
  };
  const started = performance.now();
  const baseline = snapshot();
  let last = baseline, samples = 1, failed = false, report;
  const peak = {...baseline};
  const sample = () => {
    if (failed) return;
    try {
      last = snapshot();
      samples++;
      for (const field of fields) peak[field] = Math.max(peak[field], last[field]);
    } catch { failed = true; }
  };
  const timer = setInterval(sample, intervalMs);
  timer.unref();
  return Object.freeze({
    stop() {
      if (report) return report;
      clearInterval(timer);
      sample();
      report = Object.freeze({scope: 'sampled-controller-process-memory',
        status: failed ? 'incomplete' : 'observed', intervalMs, samples,
        elapsedMs: performance.now() - started, baseline, last,
        observedPeak: Object.freeze({...peak}),
        peakAboveBaseline: Object.freeze(Object.fromEntries(fields.map(field => [field, peak[field] - baseline[field]]))),
        ...(failed ? {error: 'MemorySamplingFailed'} : {}),
      });
      return report;
    },
  });
}
