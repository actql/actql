export interface ResourceSample {
  cpuAvailable?: boolean;
  childCpuAvailable?: boolean;
  cpuUserUs?: number | null;
  cpuSystemUs?: number | null;
  cpuScope?: string | null;
  peakRssBytes?: number | null;
  rssScope?: string | null;
}
interface WallSample extends ResourceSample {
  wallNs: number;
}
type PublicClock = 'startNs' | 'observedNs' | 'closeStartNs' | 'closeEndNs' | 'exitNs' | 'endNs';
export interface PublicLatencySample extends WallSample {
  iteration?: number;
  completed?: boolean;
  verified?: boolean;
  publicTiming?: {kind: string} & Partial<Record<PublicClock, number>>;
}

export const publicLatencyTarget = Object.freeze({p95Ms: 200, maxMs: 200});
export const integer = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) >= 0;
export const requireValue = (condition: unknown, message: string) => { if (!condition) throw new Error(message); };

export function latencySummary(samples: readonly WallSample[], minimum: number) {
  requireValue(integer(minimum) && minimum > 0, 'A nonzero sample minimum is required');
  for (const row of samples) {
    requireValue(integer(row.wallNs) && integer(row.cpuUserUs) && integer(row.cpuSystemUs), 'Invalid wall/CPU sample');
  }
  const values = samples.map(row => row.wallNs / 1e6).sort((a, b) => a - b);
  const n = values.length;
  return {count: n, medianMs: n ? (values[Math.floor((n - 1) / 2)] + values[Math.floor(n / 2)]) / 2 : null,
    // A small diagnostic never supplies an acceptance p95.
    p95Ms: n >= minimum ? values[Math.ceil(n * 0.95) - 1] : null,
    maxMs: n ? values[n - 1] : null, quantile: 'nearest-rank', minimum};
}

type NoObservation = {available: false; scopes?: never};
type ObservedCPU = {available: true; scopes: string[]} & ReturnType<typeof latencySummary>;
type ObservedRSS = {available: true; scopes: string[]; maximumBytes: number};
export function resourceSummary(samples: readonly ResourceSample[], minimum: number): {
  cpu: NoObservation | ObservedCPU; rss: NoObservation | ObservedRSS;
} {
  const cpuAvailable = samples.length > 0 && samples.every(row =>
    row.cpuAvailable !== false && row.childCpuAvailable !== false &&
    integer(row.cpuUserUs) && integer(row.cpuSystemUs) && typeof row.cpuScope === 'string' && row.cpuScope.length > 0);
  const rssAvailable = samples.length > 0 && samples.every(row =>
    integer(row.peakRssBytes) && row.peakRssBytes > 0 && typeof row.rssScope === 'string' && row.rssScope.length > 0);
  return {cpu: cpuAvailable ? {available: true, scopes: [...new Set(samples.map(row => row.cpuScope!))],
    ...latencySummary(samples.map(row => ({wallNs: (row.cpuUserUs! + row.cpuSystemUs!) * 1000,
      cpuUserUs: row.cpuUserUs, cpuSystemUs: row.cpuSystemUs})), minimum)} : {available: false},
  rss: rssAvailable ? {available: true, scopes: [...new Set(samples.map(row => row.rssScope!))],
    maximumBytes: Math.max(...samples.map(row => row.peakRssBytes!))} : {available: false}};
}

// These are actual clocks around the existing public caller and its row
// oracle, not validation-call counters or inferred work durations. Child
// clocks are compared by elapsed time only, never by cross-process origin.
export function assessPublicLatencySamples(samples: readonly PublicLatencySample[], minimum: number,
  operation: string) {
  const summary = latencySummary(samples, minimum), failures: string[] = [], missing: string[] = [];
  for (const row of samples) {
    if (row.completed !== true || row.verified !== true) continue;
    const timing = row.publicTiming;
    if (!timing) {missing.push(`sample ${row.iteration}: public completion timing`); continue;}
    const names: PublicClock[] = timing.kind === 'process-result-close'
      ? ['startNs', 'observedNs', 'closeStartNs', 'closeEndNs', 'endNs']
      : timing.kind === 'cli-result-exit' ? ['startNs', 'exitNs', 'observedNs', 'endNs']
        : ['startNs', 'observedNs', 'endNs'];
    const allowed = operation.startsWith('warm-')
      ? [operation === 'warm-status' ? 'public-status' : 'public-result']
      : operation.endsWith('-process-first-result')?['process-first-result']
        : ['process-result-close', 'cli-result-exit'];
    if (!allowed.includes(timing.kind) || names.some(name => !integer(timing[name])) ||
        names.some((name, index) => index > 0 && timing[name]! < timing[names[index - 1]]!) ||
        timing.endNs! - timing.startNs! > row.wallNs) {
      failures.push(`sample ${row.iteration}: public timer excludes completion or close`);
    }
  }
  if (summary.p95Ms !== null && summary.p95Ms > publicLatencyTarget.p95Ms) failures.push('public E2E p95 exceeds 200ms');
  if (summary.maxMs !== null && summary.maxMs > publicLatencyTarget.maxMs) failures.push('public E2E observed max exceeds 200ms');
  return {summary, failures, missing};
}
