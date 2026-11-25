import test from 'node:test';
import assert from 'node:assert/strict';
import {runtimeCore, ledgerUsageSnapshot, ledgerUsageDiagnostic, ledgerUsageHasPendingResources} from './runtime-core.mjs';
import {ledgerUsageFields} from './ledger-contract.generated.mjs';
import {runInstalledStrategy} from './strategy.mjs';
import {createExecutionSiteControlFixture} from './execution-site-control.fixture.mjs';

const camel = (name: typeof ledgerUsageFields[number]['name']) =>
  name.replace(/_([a-z])/gu, (_, letter) => letter.toUpperCase()) as keyof ReturnType<typeof ledgerUsageSnapshot>;

test('strategy usage preserves every actual Core field and its original nonzero value', () => {
  const setup = {};
  const values = ledgerUsageFields.map(({bits}, index) =>
    bits === 64 ? (1n << 53n) + BigInt(index) : BigInt(index + 101));
  const original = [...values];
  let reads = 0;
  const core = runtimeCore({strategyRemoteManagedOutputEvidenceKind: () => 'unused fixture metadata',
    strategyHostUsage(actual: object) {
    assert.strictEqual(actual, setup);
    reads++;
    return values;
  }});
  const usage = core.usage(setup);
  assert.deepEqual(Object.keys(usage), ledgerUsageFields.map(({name}) => camel(name)));
  for (const [index, {name}] of ledgerUsageFields.entries()) {
    assert.equal(usage[camel(name)], original[index], name);
  }
  assert.equal(reads, 1);
  assert(Object.isFrozen(usage));
  values.fill(0n);
  assert.equal(usage.reservedAttempts, 103n);
  assert.equal(usage.liveReservations, 105n);
  assert.equal(usage.liveDelegations, 106n);
  assert.equal(usage.uncertainTransferBytes, (1n << 53n) + 7n);
  assert.equal(usage.peakRetentionBytes, (1n << 53n) + 12n);
});

test('strategy usage refuses a missing or extended runtime layout without padding fields', () => {
  for (const values of [Array(8).fill(1n), Array(ledgerUsageFields.length + 1).fill(1n), {}]) {
    const core = runtimeCore({strategyRemoteManagedOutputEvidenceKind: () => 'unused fixture metadata',
      strategyHostUsage: () => values});
    assert.throws(() => core.usage({}), {name: 'TypeError', message: 'InvalidStrategyLedgerUsage'});
  }
});

test('shared usage adapter preserves each pending counter and only Core-owned spent exclusions', () => {
  const spent = new Set(['planning_work', 'attempts', 'transferred_bytes', 'peak_retention_bytes']);
  for (const [index, {name}] of ledgerUsageFields.entries()) {
    const values = Array(ledgerUsageFields.length).fill(0n);
    values[index] = 17n;
    assert.equal(ledgerUsageHasPendingResources(values), !spent.has(name), name);
    assert.equal(ledgerUsageSnapshot(values)[camel(name)], 17n);
    assert.equal(ledgerUsageDiagnostic(values)[camel(name)], '17');
  }
});

test('all shared usage projections refuse old sparse noninteger and out-of-range layouts', () => {
  const malformed: unknown[] = [Array(9).fill(0n), Array(14).fill(0n), Array(13), {}];
  for (const [index, value] of [[0, 1], [0, -1n], [0, 2147483648n], [12, 9223372036854775808n]] as const) {
    const values = Array(13).fill(0n); values[index] = value; malformed.push(values);
  }
  for (const value of malformed) for (const project of [ledgerUsageSnapshot, ledgerUsageDiagnostic, ledgerUsageHasPendingResources]) {
    assert.throws(() => project(value), {name:'TypeError', message:'InvalidStrategyLedgerUsage'});
  }
});

// Driver protocol controls only. Actual captured-DAG hook/loan retirement is
// exercised by the corresponding client_local_host component control.
type StrategyOptions = Parameters<typeof runInstalledStrategy>[0];
type StrategyRuntime = StrategyOptions['runtime'];

function completedCleanupFixture({waiting = false, stopFailure}: {waiting?: boolean; stopFailure?: unknown} = {}) {
  const setup = {}, registration = {}, output = {};
  const events: string[] = [];
  let complete = false, selected = false, stopped = false, stops = 0;
  const core = {
    siteControl: createExecutionSiteControlFixture(),
    count: () => 2,
    next: () => selected ? undefined : (selected = true, {index: 1}),
    task: (value: Readonly<{index: number}>) => value.index,
    registration: () => registration,
    taskCapacity: () => [0n, 0n],
    completed: () => complete,
    finished: () => complete,
    stop(original: object) {
      assert.strictEqual(original, setup);
      events.push('stop'); stops++;
      if (stopFailure !== undefined) throw stopFailure;
      stopped = true;
    },
    closeOutputs(original: object) {assert.strictEqual(original, setup); events.push('core-output-close');},
    output: () => complete ? output : undefined,
    usage: () => ({}), explain: () => ({}),
  };
  const contribution = {registration, run() {
    events.push('compute');
    if (waiting) return {status: 'waiting_checkpoint', checkpoint: {}};
    complete = true;
    return {close() {events.push('output-close');}};
  }};
  return {setup, core, contribution, output, events,
    stopped: () => stopped, stops: () => stops};
}

test('completed strategy close stops its original DAG before output and logical holder retirement', async () => {
  const f = completedCleanupFixture();
  const execution = await runInstalledStrategy({setup: f.setup,
    runtime: {core: f.core, contributions: [f.contribution]} as StrategyRuntime});
  assert.equal(execution.status, 'host-tasks-completed');
  assert.strictEqual(execution.output(1), f.output);
  assert.equal(f.stops(), 0, 'The successful output remains available until its owner closes');
  execution.close();
  assert.equal(f.stopped(), true, 'Logical holder retirement requires the same captured DAG stop');
  assert.deepEqual(f.events, ['compute', 'stop', 'output-close', 'core-output-close']);
  assert.equal(execution.status, 'host-tasks-completed', 'Physical disposal is not Run cancellation');
  assert.equal(execution.failure, undefined);
  execution.close();
  assert.equal(f.stops(), 1);
  assert.equal(await execution.cleanup(), true);
  assert.equal(execution.cleanupPending(), false);
});

test('completed strategy stop failure retains original cleanup authority while other releases run', async () => {
  let pending = true, retries = 0;
  const cleanupHandle = Object.freeze({status: () => ({pending}),
    retry() {retries++; pending = false;}});
  const original = Object.assign(new Error('original completed stop failed'), {cleanupHandle});
  const f = completedCleanupFixture({stopFailure: original});
  const execution = await runInstalledStrategy({setup: f.setup,
    runtime: {core: f.core, contributions: [f.contribution]} as StrategyRuntime});
  assert.throws(() => execution.close(), error => error === original);
  assert.deepEqual(f.events, ['compute', 'stop', 'output-close', 'core-output-close']);
  assert.equal(execution.status, 'host-tasks-completed');
  assert.equal(execution.cleanupPending(), true);
  assert.equal(await execution.cleanup(), true);
  assert.equal(retries, 1);
  assert.equal(execution.cleanupPending(), false);
  execution.close();
  assert.equal(f.stops(), 1, 'Close cannot silently retry the failed original stop');
});

test('waiting strategy close does not add a completed-run stop or erase its original checkpoint', async () => {
  const f = completedCleanupFixture({waiting: true});
  const execution = await runInstalledStrategy({setup: f.setup,
    runtime: {core: f.core, contributions: [f.contribution]} as StrategyRuntime});
  assert.equal(execution.status, 'host-tasks-waiting');
  const originalCheckpoint = execution.checkpoint;
  assert.equal(f.stops(), 1, 'The existing checkpoint dispatch already owns its physical stop');
  execution.close();
  assert.equal(f.stops(), 1);
  assert.strictEqual(execution.checkpoint, originalCheckpoint);
  assert.equal(execution.status, 'host-tasks-waiting');
  assert.equal(await execution.cleanup(), true);
});

test('completed strategy stop without recovery authority remains pending after independent output close', async () => {
  const original = new Error('original stop without recovery');
  const f = completedCleanupFixture({stopFailure: original});
  const execution = await runInstalledStrategy({setup: f.setup,
    runtime: {core: f.core, contributions: [f.contribution]} as StrategyRuntime});
  assert.throws(() => execution.close(), error => error === original);
  assert.deepEqual(f.events, ['compute', 'stop', 'output-close', 'core-output-close']);
  assert.equal(await execution.cleanup(), false);
  assert.equal(execution.cleanupPending(), true);
  execution.close();
  assert.equal(f.stops(), 1);
  assert.equal(await execution.cleanup(), false);
  assert.equal(execution.cleanupPending(), true);
});


test('a controlled Driver waits at entry and after one Step before selecting the next task', async () => {
  const f = completedCleanupFixture();
  const controller = new AbortController();
  const waits = [Promise.withResolvers<() => void>(), Promise.withResolvers<() => void>()];
  let current = 'paused', selected = 0, completed = 0, waiting = 0;
  Object.assign(f.core, {
    count: () => 2,
    nextTask(actual: object) {
      assert.strictEqual(actual, f.setup);
      assert.equal(current, 'runnable');
      return selected;
    },
    next() {
      assert.equal(current, 'runnable');
      return {index: selected++};
    },
    completed: (_setup: object, index: number) => index < completed,
    finished: () => completed === 2,
    output: (_setup: object, index: number) => index < completed ? f.output : undefined,
  });
  Object.assign(f.contribution, {
    beforeNext() {f.events.push('prepare');},
    run({index}: {index: number}) {
      f.events.push(`compute-${index}`);
      completed++;
      current = completed === 2 ? 'completed' : 'paused';
      return {};
    },
  });
  const running = runInstalledStrategy({setup: f.setup,
    runtime: {core: f.core, contributions: [f.contribution]},
    control: {signal: controller.signal, taskControl: {
      phase(actual) {assert.strictEqual(actual, f.setup); return current;},
      waitForResume(actual, signal) {
        assert.strictEqual(actual, f.setup);
        assert.strictEqual(signal, controller.signal);
        const resume = Promise.withResolvers<void>();
        waits[waiting++].resolve(() => {current = 'runnable'; resume.resolve();});
        return resume.promise;
      },
    }},
  });
  const start = await waits[0].promise;
  assert.deepEqual(f.events, []);
  start();
  const resume = await waits[1].promise;
  assert.deepEqual(f.events, ['prepare', 'compute-0']);
  assert.equal(f.stops(), 0);
  resume();
  const execution = await running;
  assert.equal(execution.status, 'host-tasks-completed');
  assert.deepEqual(f.events, ['prepare', 'compute-0', 'prepare', 'compute-1']);
  execution.close();
});

test('cancelling a paused Driver stops the same setup before task selection', async () => {
  const f = completedCleanupFixture();
  const controller = new AbortController(), waiting = Promise.withResolvers<void>();
  const failure = new Error('cancel the paused original');
  f.core.next = () => assert.fail('A paused setup cannot enter task selection');
  const running = runInstalledStrategy({setup: f.setup,
    runtime: {core: f.core, contributions: [f.contribution]},
    control: {signal: controller.signal, taskControl: {
      phase: () => 'paused',
      waitForResume(actual, signal) {
        assert.strictEqual(actual, f.setup);
        const interrupt = new Promise((_, reject) => {
          signal.addEventListener('abort', () => reject(signal.reason), {once: true});
        });
        waiting.resolve();
        return interrupt;
      },
    }},
  });
  await waiting.promise;
  controller.abort(failure);
  const execution = await running;
  assert.equal(execution.status, 'host-tasks-failed');
  assert.strictEqual(execution.failure, failure);
  assert.equal(f.stops(), 1);
  assert.deepEqual(f.events, ['stop']);
  execution.close();
});
