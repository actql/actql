import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import * as core from '../host-common/runtime-core.mjs';
import {StrategyHostError} from '../host-common/strategy.mjs';

function originalFunction(file, name, ports) {
  const text = readFileSync(new URL(file, import.meta.url), 'utf8');
  let expression;
  function visit(node) {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'FunctionDeclaration' && node.id.name === name) expression = node;
    if (node.type === 'VariableDeclarator' && node.id.name === name) expression = node.init;
    for (const value of Object.values(node)) Array.isArray(value) ? value.forEach(visit) : visit(value);
  }
  visit(parse(text, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert(expression, name);
  return Function(...Object.keys(ports), `return (${text.slice(expression.start, expression.end)});`)(...Object.values(ports));
}

function dispatchCleanup(values) {
  const setup = {}, entry = {pendingSetup: setup};
  const calls = [];
  const moon = {strategyHostStop(actual) {assert.equal(actual, setup); calls.push('stop');},
    strategyHostCloseOutputs(actual) {assert.equal(actual, setup); calls.push('outputs');},
    strategyHostUsage(actual) {assert.equal(actual, setup); calls.push('usage'); return values;}};
  const cleanup = originalFunction('client-dispatch-owner.mjs', 'settleCleanup', {
    moon, ledgerUsageHasPendingResources: core.ledgerUsageHasPendingResources,
    settleCleanupHandle: async actual => assert.equal(actual, entry),
    observeStop() {assert.fail('no physical stop observation in this component');},
    observation: undefined,
  });
  return {entry, calls, cleanup: () => cleanup(entry)};
}

test('actual dispatch cleanup retains zero-byte reserved attempts and holdings', async () => {
  for (const index of [2, 3]) {
    const values = Array(13).fill(0n); values[index] = 1n;
    const f = dispatchCleanup(values);
    await assert.rejects(f.cleanup(), {message: 'ClientDispatchCleanupPending'});
    assert(f.entry.pendingSetup);
    values[index] = 0n;
    await f.cleanup();
    assert.equal(f.entry.pendingSetup, undefined);
  }
});

test('actual dispatch cleanup ignores only the original spent counters', async () => {
  const f = dispatchCleanup([7n, 3n, 0n, 0n, 0n, 0n, 83n, 0n, 0n, 0n, 0n, 0n, 211n]);
  await f.cleanup();
  assert.equal(f.entry.pendingSetup, undefined);
  assert.deepEqual(f.calls, ['stop', 'outputs', 'usage']);
});

test('actual acquired-Effect and dispatch diagnostics preserve the complete same-layout values', () => {
  const values = [101n, 102n, 103n, 104n, 105n, 106n, 107n, 108n, 109n, 110n, 111n, 112n, 113n];
  const expected = {planningWork:'101', attempts:'102', reservedAttempts:'103', holdings:'104',
    liveReservations:'105', liveDelegations:'106', transferredBytes:'107', uncertainTransferBytes:'108',
    reservedTransferBytes:'109', heldBytes:'110', reservedRetentionBytes:'111', reservedExecutionBytes:'112', peakRetentionBytes:'113'};
  const ledger = {}, host = {}, checkedHost = {}, runtime = {};
  const moon = {clientProgramMultiCapturedLedgerUsage(actual) {assert.equal(actual, ledger); return values;},
    clientProgramLocalEffectHostRuntime(actual) {assert.equal(actual, checkedHost); return runtime;},
    strategyHostUsage(actual) {assert.equal(actual, runtime); return values;}};
  const resourceUsage = originalFunction('client-dispatch-owner.mjs', 'resourceUsage', {
    moon, ledgerUsageDiagnostic: core.ledgerUsageDiagnostic,
  });
  assert.deepEqual(resourceUsage(ledger), expected);
  for (const selectedLedger of [undefined, ledger]) {
    const diagnostics = [];
    const observeUsage = originalFunction('acquired-effect-computation.mjs', 'observeUsage', {
      ledger: selectedLedger, checkedHost, moon,
      ledgerUsageDiagnostic: core.ledgerUsageDiagnostic,
      diagnostic: (name, facts) => diagnostics.push({name, facts}),
    });
    observeUsage('same-original', {host});
    assert.deepEqual(diagnostics, [{name:'same-original', facts:{host, resourceUsage:expected}}]);
  }
});

test('actual preflight cleanup retains every current counter while preserving spent history', () => {
  for (const index of [2, 3, 4, 5, 7, 8, 9, 10, 11]) {
    const values = [7n, 3n, 0n, 0n, 0n, 0n, 83n, 0n, 0n, 0n, 0n, 0n, 211n];
    values[index] = 1n;
    const setup = {}, active = new WeakSet([setup]), releasedPreflightSetups = new WeakSet();
    let stops = 0, outputs = 0;
    const create = originalFunction('../host-common/strategy.mjs', 'preflightSetupCleanup', {
      StrategyHostError, active, releasedPreflightSetups,
      ledgerUsageSnapshotHasPendingResources: core.ledgerUsageSnapshotHasPendingResources,
    });
    const owner = create({setup, core: {
      stop(actual) {assert.equal(actual, setup); stops++;},
      closeOutputs(actual) {assert.equal(actual, setup); outputs++;},
      usage(actual) {assert.equal(actual, setup); return core.ledgerUsageSnapshot(values);},
    }});
    assert.throws(() => owner.cleanup(), {code:'PublicationPreflightCleanupPending'});
    assert.equal(owner.cleanupPending(), true);
    assert(active.has(setup)); assert(!releasedPreflightSetups.has(setup));
    values[index] = 0n;
    assert.equal(owner.cleanup(), true);
    assert.equal(owner.cleanupPending(), false);
    assert(!active.has(setup)); assert(releasedPreflightSetups.has(setup));
    assert.equal(stops, 1); assert.equal(outputs, 1);
  }
});
