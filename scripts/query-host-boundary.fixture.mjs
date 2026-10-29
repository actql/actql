// Protocol peers for the real JS driver; no Common semantic completion proof.
import assert from 'node:assert/strict';
import {createExecutionSiteControlFixture} from '../adapters/host-common/execution-site-control.fixture.mjs';

function fixture() {
  const registration = {name: 'same'}, setup = {};
  let selected = false, completed = false;
  const core = {
    siteControl: createExecutionSiteControlFixture(),
    count: () => 2,
    next() { if (selected) return; selected = true; return {registration}; },
    task: () => 1, registration: task => task.registration,
    taskCapacity: () => [0n, 0n], completed: () => completed,
    finished: () => completed, stop() {}, closeOutputs() {},
    output: () => completed ? 1 : undefined,
    usage: () => ({planningWork: 0n, attempts: 0n, reservedAttempts: 0n,
      holdings: 0n, liveReservations: 0n, liveDelegations: 0n,
      transferredBytes: 0n, uncertainTransferBytes: 0n,
      reservedTransferBytes: 0n, heldBytes: 0n,
      reservedRetentionBytes: 0n, reservedExecutionBytes: 0n,
      peakRetentionBytes: 0n}),
  };
  return {registration, setup, core, complete() { completed = true; }};
}

// This call is the driver's internal API, not a public injection surface. R7
// owns its argument refactoring; only this test adapter needs to follow it.
function invoke(run, f, entries, {authorization, observeCompletion,
  beforeCompute, retainPreflightCleanup} = {}) {
  return run({
    setup: f.setup,
    runtime: {core: f.core, contributions: entries, authorization},
    control: {observeCompletion},
    publication: {beforeCompute},
    cleanup: {retainPreflightCleanup},
  });
}

export async function hostApprovalBoundary({runInstalledStrategy: run}) {
  const f = fixture();
  let sends = 0;
  const decision = Object.freeze({action: 'deny'});
  const result = await invoke(run, f, [{registration: f.registration, run() {
    sends++; f.complete();
  }}], {authorization: {isProtectedSite: () => true, cover() {},
    authorize: async () => decision}});
  try {
    assert.equal(sends, 0, 'Host approval: a refused activation must not start Compute');
    assert.equal(result.status, 'host-tasks-failed');
    assert.equal(result.failure.authorization, decision);
  } finally { await result.close(); }
}

export async function hostCompletionBoundary({runInstalledStrategy: run}) {
  for (const kind of ['foreign-registration', 'callback-only']) {
    const f = fixture();
    let sends = 0, observed = 0;
    const result = await invoke(run, f, [{registration: kind === 'foreign-registration'
      ? {name: 'same'} : f.registration, run() { sends++; return {output: 'unverified'}; }}],
    {observeCompletion() { observed++; }});
    try {
      assert.equal(observed, 0, 'Host completion: callback success is not Common publication');
      assert.equal(sends, kind === 'foreign-registration' ? 0 : 1,
        'Host registration: equal names do not confer an opaque registration');
      assert.equal(result.status, 'host-tasks-failed');
      assert.equal(result.failure.code, kind === 'foreign-registration'
        ? 'MissingStrategyImplementation' : 'TaskNotCompleted',
      'Host completion: preserve the first typed ownership/completion refusal');
    } finally { await result.close(); }
  }
}

export async function hostPreflightCustodyBoundary({runInstalledStrategy: run}) {
  const f = fixture(), events = [], primary = new Error('preflight failure');
  const closeFailure = new Error('stop failed');
  let retained, attempts = 0, failure;
  f.core.stop = () => { events.push('stop'); if (++attempts === 1) throw closeFailure; };
  try {
    await invoke(run, f, [], {beforeCompute() { throw primary; },
      retainPreflightCleanup(owner) { events.push('retained'); retained = owner; }});
    assert.fail('preflight must refuse');
  } catch (error) { failure = error; }
  assert.equal(events[0], 'retained',
    'preflight custody: transfer the exact cleanup owner before fallible stop');
  assert.equal(failure.primaryFailure, primary);
  assert.equal(failure.cleanupHandle, retained);
  assert.equal(retained.status().pending, true);
  assert.equal(retained.retry().pending, false);
  assert.equal(attempts, 2);
  assert.equal(retained.retry().pending, false);
  assert.equal(attempts, 2);
}
