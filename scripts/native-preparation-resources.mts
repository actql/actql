// Read-only process observations for this one CI preparation, never admission.
import assert from 'node:assert/strict';
import {Worker, isMainThread, parentPort, workerData} from 'node:worker_threads';
import {spawnSync, execFileSync} from 'node:child_process';
import {openSync, closeSync, writeSync, ftruncateSync, constants} from 'node:fs';
import {availableParallelism, totalmem} from 'node:os';
import {availableVerificationMemory} from './local-checks-guard.mjs';

type ProcessRow = {pid: number; parent: number; rss: number; us: number; start: string};
type Samples<Record> = {samples: Record[]; unavailable?: string};
type ResourceSample = ReturnType<typeof preparationProcessSample>['record'] & {
  elapsedNs: number; observed_system_available_memory_bytes: number;
};
type ResourceConfiguration = Readonly<{rootPid: number; output: string; deadline: number; source: string; target: string}>;
type ResourceReport = Samples<ResourceSample> & {
  kind: string; source: string; target: string; rootPid: number; intervalMs: number; startedEpochMs: number;
  complete: boolean; cpuThreads: number; totalMemoryBytes: number; scope: string; endedEpochMs?: number;
  max_sample_sum_process_rss_bytes?: number; originalStart?: string;
};
type WorkerPort = {
  on(event: 'message', handle: (value?: {unavailable?: boolean}) => void): unknown;
  on(event: 'error', handle: () => void): unknown;
  on(event: 'exit', handle: (code: number) => void): unknown;
  postMessage(message: 'stop'): void;
  terminate(): Promise<number>;
};
type JoinResult = {failed: boolean};
type Observer = {close(): Promise<JoinResult | void>};
type ObserverOptions = {createWorker?: () => WorkerPort; joinMs?: number};
type ResourceOptions<Configuration> = {
  startObserver?: (configuration: Configuration) => Observer;
  unavailable?: () => void;
};

const intervalMs = 5000, maxBytes = 1024 * 1024, metadataTimeoutMs = 1000;
const kind = 'native-preparation-process-observation';
export function preparationProcessSample(text: string, rootPid: number, originalStart?: string,
  previous: ReadonlyMap<number, ProcessRow> = new Map()) {
  const lines = text.trim().split('\n'); assert(lines.length <= 4096, 'Process metadata row bound');
  const processes = new Map<number, ProcessRow>();
  for (const line of lines) {
    const match = /^\s*(\d+)\s+(\d+)\s+(\d+)\s+([\d:.\-]+)\s+([ -~]{1,64})$/u.exec(line);
    assert(match, 'Unavailable process metadata');
    const [pid, parent, rss] = match.slice(1, 4).map(Number);
    const cpu = /^(?:(\d+)-)?(?:(\d+):)?(\d+):(\d+(?:\.\d+)?)$/u.exec(match[4]);
    assert(cpu, 'Unavailable own CPU time');
    const us = Math.round(((Number(cpu[1] ?? 0) * 24 + Number(cpu[2] ?? 0)) * 3600 +
      Number(cpu[3]) * 60 + Number(cpu[4])) * 1e6);
    assert(Number(cpu[4]) < 60 && (cpu[2] === undefined || Number(cpu[3]) < 60), 'Invalid own CPU clock');
    assert([pid, parent, rss, us].every(x => Number.isSafeInteger(x) && x >= 0) && pid > 0 && !processes.has(pid));
    processes.set(pid, {pid, parent, rss: rss * 1024, us, start: match[5]});
  }
  const root = processes.get(rootPid);
  assert(root && (originalStart === undefined || root.start === originalStart), 'Original preparation absent or replaced');
  const selected = new Map([[rootPid, root]]);
  for (;;) {
    const before = selected.size;
    for (const [pid, row] of processes) if (!selected.has(pid) && selected.has(row.parent)) selected.set(pid, row);
    if (before === selected.size) break;
  }
  let rss = 0, cpu = 0, delta = 0, compared = 0;
  for (const [pid, row] of selected) {
    rss += row.rss; cpu += row.us;
    const old = previous.get(pid);
    if (old?.start === row.start && row.us >= old.us) {delta += row.us - old.us; compared++;}
  }
  assert([rss, cpu, delta].every(Number.isSafeInteger), 'Process observation overflow');
  return {originalStart: root.start, selected, record: {
    sample_sum_process_rss_bytes: rss, sample_sum_own_cpu_time_us: cpu,
    sample_observed_own_cpu_delta_us: delta, observed_processes: selected.size, compared_processes: compared,
  }};
}

export function appendPreparationResourceSample<Record>(report: Samples<Record>, record: Record,
  {maximumSamples, maximumBytes = maxBytes}: {maximumSamples: number; maximumBytes?: number}) {
  if (report.samples.length >= maximumSamples) {report.unavailable = 'sample-count-bound'; return false;}
  report.samples.push(record);
  // Reserve the bounded terminal fields before retaining another sample.
  if (Buffer.byteLength(JSON.stringify(report)) + 256 > maximumBytes) {
    report.samples.pop(); report.unavailable = 'output-bound'; return false;
  }
  return true;
}

// The worker is independent of the synchronous compiler calls in the main
// thread. It has no command/environment/body/Store reader and controls no builder.
function observe(configuration: ResourceConfiguration) {
  const {rootPid, output, deadline, source, target} = configuration;
  const started = process.hrtime.bigint(), samples: ResourceSample[] = [];
  const maximumSamples = Math.ceil((deadline - Date.now()) / intervalMs) + 1;
  assert(Number.isSafeInteger(rootPid) && rootPid > 0 && Number.isFinite(deadline) &&
    maximumSamples > 0 && maximumSamples <= 10000, 'Finite original observation deadline required');
  const fd = openSync(output, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
  const report: ResourceReport = {kind, source, target, rootPid, intervalMs, startedEpochMs: Date.now(), complete: false,
    cpuThreads: availableParallelism(), totalMemoryBytes: totalmem(), samples,
    scope: 'Snapshot-observed preparation descendants; own user+system CPU without ps -S. Fast/exited/reparented processes and sub-second PID reuse may be missed. RSS sums double-count shared pages. The max sample is a lower bound only on the peak of that same sum metric, never on unique physical RAM/headroom/allocation. System availability is global and unreserved. Observer overhead is included.'};
  let timer: NodeJS.Timeout | undefined, previous = new Map<number, ProcessRow>(),
    originalStart: string | undefined, stopped = false;
  const save = () => {
    const bytes = JSON.stringify(report) + '\n';
    assert(Buffer.byteLength(bytes) <= maxBytes, 'Observation output bound');
    ftruncateSync(fd, 0); writeSync(fd, bytes, 0, 'utf8'); return true;
  };
  const stop = () => {
    if (stopped) return; stopped = true; clearInterval(timer);
    report.endedEpochMs = Date.now(); report.complete = report.unavailable === undefined;
    report.max_sample_sum_process_rss_bytes = Math.max(0, ...samples.map(x => x.sample_sum_process_rss_bytes));
    try {save(); parentPort!.postMessage({unavailable: report.unavailable !== undefined});}
    finally {closeSync(fd); parentPort!.close();}
  };
  const sample = () => {
    try {
      if (Date.now() >= deadline || samples.length >= maximumSamples) {report.unavailable = 'original-deadline-or-count-bound'; stop(); return;}
      const env = {...process.env, LC_ALL: 'C'};
      // No -S: ps must not add exited-child CPU to a parent's own CPU.
      const current = spawnSync('/bin/ps', ['-axo', 'pid=,ppid=,rss=,time=,lstart='],
        {env, encoding: 'utf8', timeout: metadataTimeoutMs, maxBuffer: maxBytes});
      assert.equal(current.status, 0); assert.equal(current.signal, null); assert.equal(current.error, undefined);
      const value = preparationProcessSample(current.stdout, rootPid, originalStart, previous);
      previous = value.selected; originalStart = value.originalStart; report.originalStart = originalStart;
      const memory = execFileSync('/usr/bin/memory_pressure', ['-Q'],
        {env, encoding: 'utf8', timeout: metadataTimeoutMs, maxBuffer: 8192});
      const retained = appendPreparationResourceSample(report,
        {...value.record, elapsedNs: Number(process.hrtime.bigint() - started),
          observed_system_available_memory_bytes: availableVerificationMemory('darwin', memory, report.totalMemoryBytes)},
        {maximumSamples});
      save(); if (!retained) stop();
    } catch {report.unavailable = 'metadata-unavailable'; stop();}
  };
  parentPort!.on('message', message => {if (message === 'stop') stop();});
  sample();
  if (!stopped) timer = setInterval(sample, intervalMs);
}

export function startNativePreparationResourceObserver(configuration: ResourceConfiguration, options?: ObserverOptions):
  {close(): Promise<JoinResult>};
export function startNativePreparationResourceObserver(configuration: object,
  options: ObserverOptions & {createWorker: () => WorkerPort}): {close(): Promise<JoinResult>};
export function startNativePreparationResourceObserver(configuration: object, {createWorker = () =>
  new Worker(new URL(import.meta.url), {workerData: {kind, configuration},
    resourceLimits: {maxOldGenerationSizeMb: 64}}), joinMs = 3000}: ObserverOptions = {}) {
  assert(Number.isSafeInteger(joinMs) && joinMs > 0 && joinMs <= 2147483647);
  const worker = createWorker();
  // Always join a worker exit, including a startup failure, before returning.
  let failed = false;
  const exited = new Promise<JoinResult>(resolve => {
    worker.on('message', value => {if (value?.unavailable) failed = true;});
    worker.on('error', () => {failed = true;});
    worker.on('exit', code => resolve({failed: failed || code !== 0}));
  });
  let closing: Promise<JoinResult> | undefined;
  return {close() {return closing ??= (async () => {
    try {worker.postMessage('stop');} catch {failed = true;}
    let timeout: NodeJS.Timeout | undefined;
    const bounded = new Promise<null>(resolve => {timeout = setTimeout(() => resolve(null), joinMs);});
    let result = await Promise.race([exited, bounded]); clearTimeout(timeout);
    if (result === null) {await worker.terminate(); result = {failed: true};}
    return result;
  })();}};
}

// Diagnostics never change the original constructor return/error or authorize
// publication. The original publisher runs only after original construction.
export function withNativePreparationResources<Value, Result>(configuration: ResourceConfiguration | undefined,
  construct: () => Value | PromiseLike<Value>, publish: (value: Value) => Result,
  options?: ResourceOptions<ResourceConfiguration>): Promise<Awaited<Result>>;
export function withNativePreparationResources<Configuration extends object, Value, Result>(configuration: Configuration,
  construct: () => Value | PromiseLike<Value>, publish: (value: Value) => Result,
  options: ResourceOptions<Configuration> & {startObserver: (configuration: Configuration) => Observer}): Promise<Awaited<Result>>;
export async function withNativePreparationResources<Configuration extends object, Value, Result>(
  configuration: Configuration | undefined, construct: () => Value | PromiseLike<Value>, publish: (value: Value) => Result,
  {startObserver = startNativePreparationResourceObserver as (configuration: Configuration) => Observer,
    unavailable = () => console.error('Native preparation resource observation unavailable')}: ResourceOptions<Configuration> = {}) {
  if (configuration === undefined) return publish(await construct());
  const note = () => {try {unavailable();} catch { /* Diagnostic-only failure. */ }};
  let observer: Observer | undefined, value: Value;
  try {observer = startObserver(configuration);} catch {note();}
  try {value = await construct();}
  finally {
    try {if ((await observer?.close())?.failed) note();}
    catch {note();}
  }
  return publish(value);
}

if (!isMainThread && workerData?.kind === kind) observe(workerData.configuration);
