// Protocol peers for the real JS driver; no Common semantic completion proof.
import assert from 'node:assert/strict';
import {createExecutionSiteControlFixture} from '../adapters/host-common/execution-site-control.fixture.mjs';
import {StrategyHostError} from '../adapters/host-common/strategy.mjs';

type Strategy = Pick<typeof import('../adapters/host-common/strategy.mjs'), 'runInstalledStrategy'>;
type Run = Strategy['runInstalledStrategy'];
type Options = Parameters<Run>[0];
type Runtime = Options['runtime'];
type RetainCleanup = NonNullable<NonNullable<Options['cleanup']>['retainPreflightCleanup']>;
type Controls = {
  authorization?: Runtime['authorization'];
  observeCompletion?: NonNullable<Options['control']>['observeCompletion'];
  beforeCompute?: NonNullable<Options['publication']>['beforeCompute'];
  retainPreflightCleanup?: RetainCleanup;
};

function fixture() {
  const registration = {name: 'same'}, setup = {}, dispatch = {registration};
  let selected = false, completed = false;
  const core = {
    siteControl: createExecutionSiteControlFixture(),
    count: () => 2,
    next() { if (selected) return; selected = true; return dispatch; },
    task: () => 1, registration: (selected: unknown) => {
      assert.equal(selected, dispatch);
      return dispatch.registration;
    },
    taskCapacity: () => [0n, 0n], completed: () => completed,
    finished: () => completed, stop() {}, closeOutputs() {},
    explain() { assert.fail('Refused strategy must not explain a completed run'); },
    output() {
      assert.equal(completed, false, 'Refused strategy must not expose output');
      return undefined;
    },
    usage: () => ({planningWork: 0n, attempts: 0n, reservedAttempts: 0n,
      holdings: 0n, liveReservations: 0n, liveDelegations: 0n,
      transferredBytes: 0n, uncertainTransferBytes: 0n,
      reservedTransferBytes: 0n, heldBytes: 0n,
      reservedRetentionBytes: 0n, reservedExecutionBytes: 0n,
      peakRetentionBytes: 0n}),
  } satisfies Runtime['core'];
  return {registration, setup, core, complete() { completed = true; }};
}

// The fixture invokes the same internal Strategy entry as the installed host.
function invoke(run: Run, f: ReturnType<typeof fixture>, entries: Runtime['contributions'],
  {authorization, observeCompletion, beforeCompute, retainPreflightCleanup}: Controls = {}) {
  return run({
    setup: f.setup,
    runtime: {core: f.core, contributions: entries, authorization},
    control: {observeCompletion},
    publication: {beforeCompute},
    cleanup: {retainPreflightCleanup},
  });
}

export async function hostApprovalBoundary({runInstalledStrategy: run}: Strategy) {
  const f = fixture();
  let sends = 0;
  const decision = Object.freeze({action: 'deny'});
  const result = await invoke(run, f, [{registration: f.registration, run() {
    sends++; f.complete();
    return undefined;
  }}], {authorization: {isProtectedSite: () => true, cover() {},
    authorize: async () => decision}});
  try {
    assert.equal(sends, 0, 'Host approval: a refused activation must not start Compute');
    assert.equal(result.status, 'host-tasks-failed');
    assert(result.failure instanceof Error && 'authorization' in result.failure);
    assert.equal(result.failure.authorization, decision);
  } finally { await result.close(); }
}

export async function hostCompletionBoundary({runInstalledStrategy: run}: Strategy) {
  for (const kind of ['foreign-registration', 'callback-only']) {
    const f = fixture();
    let sends = 0, observed = 0;
    // An unverified payload carries no Common completion receipt.
    const callbackResult: {output: string; status?: string} = {output: 'unverified'};
    const result = await invoke(run, f, [{registration: kind === 'foreign-registration'
      ? {name: 'same'} : f.registration, run() { sends++; return callbackResult; }}],
    {observeCompletion() { observed++; }});
    try {
      assert.equal(observed, 0, 'Host completion: callback success is not Common publication');
      assert.equal(sends, kind === 'foreign-registration' ? 0 : 1,
        'Host registration: equal names do not confer an opaque registration');
      assert.equal(result.status, 'host-tasks-failed');
      assert(result.failure instanceof Error && 'code' in result.failure);
      assert.equal(result.failure.code, kind === 'foreign-registration'
        ? 'MissingStrategyImplementation' : 'TaskNotCompleted',
      'Host completion: preserve the first typed ownership/completion refusal');
    } finally { await result.close(); }
  }
}

export async function hostPreflightCustodyBoundary({runInstalledStrategy: run}: Strategy) {
  const f = fixture(), events: string[] = [], primary = new Error('preflight failure');
  const closeFailure = new Error('stop failed');
  let retained: Parameters<RetainCleanup>[0] | undefined;
  let attempts = 0;
  let failure: unknown;
  f.core.stop = () => { events.push('stop'); if (++attempts === 1) throw closeFailure; };
  try {
    await invoke(run, f, [], {beforeCompute() { throw primary; },
      retainPreflightCleanup(owner) { events.push('retained'); retained = owner; }});
    assert.fail('preflight must refuse');
  } catch (error) { failure = error; }
  assert.equal(events[0], 'retained',
    'preflight custody: transfer the exact cleanup owner before fallible stop');
  assert(failure instanceof StrategyHostError);
  assert(retained);
  assert.equal(failure.primaryFailure, primary);
  assert.equal(failure.cleanupHandle, retained);
  assert.equal(retained.status().pending, true);
  assert.equal(retained.retry().pending, false);
  assert.equal(attempts, 2);
  assert.equal(retained.retry().pending, false);
  assert.equal(attempts, 2);
}
