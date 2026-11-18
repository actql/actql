import test from 'node:test';
import assert from 'node:assert/strict';
import {runtimeCore, ledgerUsageSnapshot, ledgerUsageDiagnostic, ledgerUsageHasPendingResources} from './runtime-core.mjs';
import {ledgerUsageFields} from './ledger-contract.generated.mjs';
import {runInstalledStrategy} from './strategy.mjs';
import {createExecutionSiteControlFixture} from './execution-site-control.fixture.mjs';

const camel = name => name.replace(/_([a-z])/gu, (_, letter) => letter.toUpperCase());

test('strategy usage preserves every actual Core field and its original nonzero value', () => {
  const setup = {};
  const values = ledgerUsageFields.map(({bits}, index) =>
    bits === 64 ? (1n << 53n) + BigInt(index) : BigInt(index + 101));
  const original = [...values];
  let reads = 0;
  const core = runtimeCore({strategyRemoteManagedOutputEvidenceKind: () => 'unused fixture metadata',
    strategyHostUsage(actual) {
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
  const malformed = [Array(9).fill(0n), Array(14).fill(0n), Array(13), {}];
  for (const [index, value] of [[0, 1], [0, -1n], [0, 2147483648n], [12, 9223372036854775808n]]) {
    const values = Array(13).fill(0n); values[index] = value; malformed.push(values);
  }
  for (const value of malformed) for (const project of [ledgerUsageSnapshot, ledgerUsageDiagnostic, ledgerUsageHasPendingResources]) {
    assert.throws(() => project(value), {name:'TypeError', message:'InvalidStrategyLedgerUsage'});
  }
});

// Driver protocol controls only. Actual captured-DAG hook/loan retirement is
// exercised by the corresponding client_local_host component control.
function completedCleanupFixture({waiting = false, stopFailure} = {}) {
  const setup = {}, registration = {}, output = {};
  const events = [];
  let complete = false, selected = false, stopped = false, stops = 0;
  const core = {
    siteControl: createExecutionSiteControlFixture(),
    count: () => 2,
    next: () => selected ? undefined : (selected = true, {index: 1}),
    task: value => value.index,
    registration: () => registration,
    taskCapacity: () => [0n, 0n],
    completed: () => complete,
    finished: () => complete,
    stop(original) {
      assert.strictEqual(original, setup);
      events.push('stop'); stops++;
      if (stopFailure !== undefined) throw stopFailure;
      stopped = true;
    },
    closeOutputs(original) {assert.strictEqual(original, setup); events.push('core-output-close');},
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
    runtime: {core: f.core, contributions: [f.contribution]}});
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
    runtime: {core: f.core, contributions: [f.contribution]}});
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
    runtime: {core: f.core, contributions: [f.contribution]}});
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
    runtime: {core: f.core, contributions: [f.contribution]}});
  assert.throws(() => execution.close(), error => error === original);
  assert.deepEqual(f.events, ['compute', 'stop', 'output-close', 'core-output-close']);
  assert.equal(await execution.cleanup(), false);
  assert.equal(execution.cleanupPending(), true);
  execution.close();
  assert.equal(f.stops(), 1);
  assert.equal(await execution.cleanup(), false);
  assert.equal(execution.cleanupPending(), true);
});
