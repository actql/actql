import assert from 'node:assert/strict';
import test from 'node:test';
import {EventEmitter} from 'node:events';
import {readFileSync} from 'node:fs';
import {parse} from 'yaml';
import {preparationProcessSample, appendPreparationResourceSample,
  startNativePreparationResourceObserver, withNativePreparationResources} from './native-preparation-resources.mjs';

const start = 'Tue Nov 17 21:00:00 2026';
const row = (pid: number, parent: number, rss: number, cpu: string, began = start) => `${pid} ${parent} ${rss} ${cpu} ${began}`;

test('preparation samples sum only observed descendants and separate own CPU counters', () => {
  const first = preparationProcessSample([
    row(10, 1, 100, '0:01.00'), row(11, 10, 200, '0:02.00'),
    row(12, 11, 300, '0:03.00'), row(20, 1, 9999, '1:39.00'),
  ].join('\n'), 10);
  const next = preparationProcessSample([
    row(10, 1, 110, '0:01.10'), row(11, 10, 210, '0:02.20'),
    row(12, 11, 310, '0:03.30'), row(20, 1, 9999, '1:39.00'),
  ].join('\n'), 10, first.originalStart, first.selected);
  assert.equal(next.record.sample_sum_process_rss_bytes, 630 * 1024);
  assert.equal(next.record.sample_sum_own_cpu_time_us, 6_600_000);
  assert.equal(next.record.sample_observed_own_cpu_delta_us, 600_000);
  assert.equal(next.record.observed_processes, 3);
});

test('preparation PID/start identity excludes reused counters and refuses missing or changed root', () => {
  const first = preparationProcessSample([row(10, 1, 100, '0:01.00'), row(11, 10, 200, '0:02.00')].join('\n'), 10);
  const next = preparationProcessSample([row(10, 1, 110, '0:01.10'),
    row(11, 10, 200, '0:10.00', 'Tue Nov 17 21:00:05 2026')].join('\n'), 10, start, first.selected);
  assert.equal(next.record.sample_observed_own_cpu_delta_us, 100_000);
  assert.equal(next.record.compared_processes, 1);
  for (const text of ['', row(11, 1, 1, '0:01.00'), row(10, 1, 1, '0:01.00', 'changed'),
    row(10, 1, 1, '0:99.99'), [row(10, 1, 1, '0:01.00'), row(10, 1, 2, '0:02.00')].join('\n')]) {
    assert.throws(() => preparationProcessSample(text, 10, start));
  }
});

test('preparation observations stop at sample and output bounds without retaining the rejected data', () => {
  const count: {samples: {n: number}[]; unavailable?: string} = {samples: []};
  assert(appendPreparationResourceSample(count, {n: 1}, {maximumSamples: 1}));
  assert(!appendPreparationResourceSample(count, {n: 2}, {maximumSamples: 1}));
  assert.deepEqual(count.samples, [{n: 1}]); assert.equal(count.unavailable, 'sample-count-bound');
  const bytes: {samples: {large: string}[]; unavailable?: string} = {samples: []};
  assert(!appendPreparationResourceSample(bytes, {large: 'x'.repeat(1024)}, {maximumSamples: 2, maximumBytes: 512}));
  assert.deepEqual(bytes.samples, []); assert.equal(bytes.unavailable, 'output-bound');
});

class WorkerPort extends EventEmitter {
  stops = 0; terminations = 0;
  declare readonly mode: string;
  constructor(mode: string) {super(); this.mode = mode;}
  postMessage(message: string) {
    assert.equal(message, 'stop'); this.stops++;
    if (this.mode === 'throw') throw new Error('StopPortFailure');
    if (this.mode === 'unavailable') this.emit('message', {unavailable: true});
    if (this.mode === 'error') this.emit('error', new Error('WorkerFailure'));
    if (this.mode !== 'pending') queueMicrotask(() => this.emit('exit', 0));
  }
  async terminate() {this.terminations++; this.emit('exit', 1); return 1;}
}

test('preparation observer closes once and joins normal, unavailable and bounded unresponsive workers', async () => {
  for (const mode of ['normal', 'unavailable', 'error', 'pending', 'throw']) {
    const worker = new WorkerPort(mode);
    const observer = startNativePreparationResourceObserver({}, {createWorker: () => worker, joinMs: 5});
    const first = observer.close(); assert.equal(observer.close(), first);
    const result = await first;
    assert.equal(result.failed, mode !== 'normal'); assert.equal(worker.stops, 1);
    assert.equal(worker.terminations, ['pending', 'throw'].includes(mode) ? 1 : 0);
  }
});

test('original preparation result and error survive observer startup, shutdown and diagnostic failures', async () => {
  const original = {}, primary = new Error('OriginalCompilerFailure');
  for (const mode of ['normal', 'startup', 'close']) {
    const order: string[] = [];
    const startObserver = () => {
      order.push('start'); if (mode === 'startup') throw new Error('ObserverUnavailable');
      return {async close() {order.push('join'); if (mode === 'close') throw new Error('CloseUnavailable');}};
    };
    const ports = {startObserver, unavailable: () => {throw new Error('DiagnosticFailure');}};
    assert.equal(await withNativePreparationResources({}, async () => {order.push('construct'); return original;},
      value => {order.push('publish'); return value;}, ports), original);
    assert.equal(order.at(-1), 'publish');
    if (mode !== 'startup') assert(order.indexOf('join') < order.indexOf('publish'));
    await assert.rejects(withNativePreparationResources({}, async () => {throw primary;},
      () => assert.fail('Failed construction cannot publish'), ports), value => value === primary);
  }
  assert.equal(await withNativePreparationResources(undefined, async () => original, value => value,
    {startObserver: () => assert.fail('Ordinary unselected invocation cannot start an observer')}), original);
  let caught = false;
  try {
    await withNativePreparationResources({}, async () => {throw undefined;},
      () => assert.fail('A fieldless original throw cannot publish'),
      {startObserver: () => ({close: async () => {throw new Error('ObserverCloseFailure');}})});
  } catch (failure) {caught = true; assert.equal(failure, undefined);}
  assert.equal(caught, true);
});

test('resource observations select only the existing Mac preparation and preserve original upload and job geometry', () => {
  const ci = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8')) as {
    jobs: Record<string, {steps?: {env?: Record<string, string>; run?: string; with?: {name?: string; path?: string}}[]}>;
  };
  const selected = Object.entries(ci.jobs).flatMap(([job, value]) => (value.steps ?? [])
    .filter(step => step.env?.ACTQL_NATIVE_PREPARATION_RESOURCE_OBSERVER === '1').map(step => ({job, step})));
  assert.deepEqual(selected.map(value => value.job), ['native-macos-workloads']);
  assert(selected[0].step.run!.includes('--lanes 2'));
  const upload = ci.jobs['native-macos-workloads'].steps!.find(step => step.with?.name?.startsWith('native-scoped-preparation-'));
  assert(upload!.with!.path!.includes('/native-scoped-preparation/**/*.json'));
  assert(!upload!.with!.path!.includes('observation.json'), 'Reuse existing diagnostic metadata, not another artifact layout');
});
