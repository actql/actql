import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openSqliteDispatchJournal} from './sqlite-dispatch-journal.mjs';
import {createRemoteDispatchRuntime, prepareRemoteRuntimeRegistration} from
  './remote-dispatch-runtime.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const runtime = runtimeCore(moon);
const managedOutputEvidenceKind =
  runtime.remoteSiteControl.managedOutputEvidenceKind;
const dispatchBudget = runtime.remoteSiteControl.prepareBudget({
  retainedBytes: 64n,
  executionBytes: 16n,
});
const dispatchBudgetCid = runtime.remoteSiteControl.budgetIdentity(
  dispatchBudget,
);

function site() {
  return runtime.siteControl.create(Object.freeze({
    key: 'site-a',
    generation: 1,
    runtimeRevision: cid('a'),
    maxConcurrentOperations: 4,
    maxConcurrentTransfers: 4,
    maxRetainedBytes: 1_048_576n,
    maxExecutionBytes: 1_048_576n,
  }));
}

function request(overrides = {}) {
  return runtime.remoteSiteControl.prepare(Object.freeze({
    coordinatorAuthority: 'coordinator-a',
    runDefinitionCid: cid('0'),
    taskKey: 'task-a',
    taskAttempt: 1,
    dispatchId: 'dispatch-a',
    siteKey: 'site-a',
    siteGeneration: 1,
    runtimeBundleCid: cid('a'),
    connectorRegistration: 'local',
    connectorRevision: 'local/1',
    strategyRevision: 'strategy/1',
    inputBindingCid:
      'sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a',
    obligationsCid: cid('2'),
    budgetCid: dispatchBudgetCid,
    evidenceIssuerCapabilityCid: cid('b'),
    grantCid: cid('4'),
    ...overrides,
  }));
}

function managedOutput(overrides = {}) {
  return Object.freeze({
    materialGeneration: 'material-generation-a',
    managedProfileCid: cid('3'),
    measurement: Object.freeze({
      rowCount: 2,
      admissionNodes: 0,
      admissionTextBytes: 0,
      admissionWork: 0,
      columnRows: Object.freeze([2]),
      columnBytes: Object.freeze([2]),
      columnNodes: Object.freeze([2]),
      columnMaxValueBytes: Object.freeze([1]),
      columnNullRows: Object.freeze([0]),
      columnAdmittedDepths: Object.freeze([10]),
    }),
    resultSchemaCid: cid('5'),
    logicalViewCid: cid('6'),
    representationCodecCid: cid('7'),
    physicalManifestCid: cid('8'),
    rowCount: 2,
    retainedBytes: 8n,
    async close() {},
    ...overrides,
  });
}

async function fixture(
  t,
  execute,
  {
    autoClose = true,
    wrapControl = value => value,
    wrapStore = value => value,
  } = {},
) {
  const root = await mkdtemp(join(tmpdir(), 'actql-remote-runtime-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const selectedSite = site();
  const control = wrapControl(runtime.remoteSiteControl);
  const journal = control.createJournal(selectedSite);
  const store = openSqliteDispatchJournal(root, {
    siteKey: 'site-a',
    siteGeneration: 1,
    runtimeRevision: cid('a'),
  });
  const registration = prepareRemoteRuntimeRegistration({
    control,
    site: selectedSite,
    runtimeBundleCid: cid('a'),
    connectorRegistration: 'local',
    connectorRevision: 'local/1',
    strategyRevision: 'strategy/1',
    operationCapabilityCid: cid('4'),
    evidenceKind: managedOutputEvidenceKind,
    issuerCapabilityCid: cid('b'),
    execute,
  });
  const bundleManifest = Object.freeze({runtimeBundleCid: cid('a')});
  const bundleHolds = new Map();
  const bundleControl = Object.freeze({
    identity: value => value.runtimeBundleCid,
  });
  const bundleStore = Object.freeze({
    active: () => Object.freeze({manifest: bundleManifest}),
    async verify(runtimeBundleCid) {
      if (runtimeBundleCid !== cid('a')) {
        throw Object.assign(new Error('bundle missing'), {
          code: 'RemoteBundleMissing',
        });
      }
      return Object.freeze({manifest: bundleManifest});
    },
    retain(runtimeBundleCid, holdId, kind) {
      if (runtimeBundleCid !== cid('a') || kind !== 'dispatch') {
        throw new Error('invalid bundle hold');
      }
      const existing = bundleHolds.get(holdId);
      if (existing !== undefined && existing !== runtimeBundleCid) {
        throw new Error('bundle hold collision');
      }
      bundleHolds.set(holdId, runtimeBundleCid);
      return true;
    },
    release(holdId) {
      return bundleHolds.delete(holdId);
    },
  });
  const dispatchRuntime = createRemoteDispatchRuntime({
    control,
    siteControl: runtime.siteControl,
    store: wrapStore(store),
    bundleStore,
    bundleControl,
    registrations: [registration],
    budgets: [dispatchBudget],
  });
  t.after(async () => {
    if (autoClose) await dispatchRuntime.close();
    store.close();
  });
  return {
    bundleHolds,
    control,
    dispatchRuntime,
    journal,
    root,
    selectedSite,
    store,
  };
}

test('registered runtime durably executes, evidences, and releases output',
  async t => {
    let executions = 0;
    let closes = 0;
    let admittedInputBinding;
    const f = await fixture(t, async ({inputBinding, inputBindingBody}) => {
      executions++;
      admittedInputBinding = inputBinding;
      assert.equal(inputBindingBody, '{}');
      return managedOutput({
        async close() { closes++; },
      });
    });
    const dispatch = request();
    assert.equal(f.dispatchRuntime.supports(dispatch), true);
    const record = f.store.accept(
      f.control.prepareAdmission(f.journal, dispatch),
      dispatch,
      f.control,
    );
    const completed = await f.dispatchRuntime.start(
      dispatch,
      record,
      undefined,
      '{}',
    );
    assert.equal(executions, 1);
    assert.equal(
      f.control.inputBindingIdentity(admittedInputBinding),
      f.control.inputBindingIdentity(f.control.prepareInputBinding('{}')),
    );
    assert.deepEqual(completed.state, [3, 2, 0, 1, 0]);
    assert.equal(completed.revision, 5);
    assert.equal(
      f.store.inspectEvidence(dispatch, f.control).execution_evidence_cid,
      f.control.evidenceIdentity(completed.evidence),
    );
    assert.throws(
      () => f.dispatchRuntime.start(dispatch, record, undefined, '{}'),
      {code: 'RemoteDispatchAlreadyStarted'},
    );
    assert.deepEqual(
      runtime.siteControl.status(f.selectedSite).slice(2, 9),
      [0n, 0n, 1n, 0n, 8n, 0n, 0n],
    );
    assert.equal(f.bundleHolds.size, 1);
    assert.equal(await f.dispatchRuntime.release(dispatch), true);
    assert.equal(closes, 1);
    assert.equal(f.bundleHolds.size, 0);
    assert.deepEqual(f.control.status(record), [3, 2, 2, 0, 0]);
    assert.deepEqual(
      runtime.siteControl.status(f.selectedSite).slice(2, 9),
      [0n, 0n, 0n, 0n, 0n, 0n, 0n],
    );
  });

test('active exact replay joins one physical start', async t => {
  let executions = 0;
  let finishExecution;
  const executionGate = new Promise(resolve => { finishExecution = resolve; });
  const f = await fixture(t, async () => {
    executions++;
    await executionGate;
    return managedOutput();
  });
  const dispatch = request({dispatchId: 'active-exact-replay'});
  const record = f.store.accept(
    f.control.prepareAdmission(f.journal, dispatch),
    dispatch,
    f.control,
  );
  const first = f.dispatchRuntime.start(dispatch, record, undefined, '{}');
  const replay = f.dispatchRuntime.start(dispatch, record, undefined, '{}');
  assert.equal(first, replay);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(executions, 1);
  finishExecution();
  assert.equal(await first, await replay);
});

test('concurrent runtime closes wait for active execution and cleanup',
  async t => {
    let enteredExecution;
    const entered = new Promise(resolve => { enteredExecution = resolve; });
    let finishExecution;
    const executionGate = new Promise(resolve => { finishExecution = resolve; });
    let closes = 0;
    const f = await fixture(t, async () => {
      enteredExecution();
      await executionGate;
      return managedOutput({async close() { closes++; }});
    }, {autoClose: false});
    const dispatch = request({dispatchId: 'concurrent-runtime-close'});
    const record = f.store.accept(
      f.control.prepareAdmission(f.journal, dispatch), dispatch, f.control,
    );
    const active = f.dispatchRuntime.start(dispatch, record, undefined, '{}');
    await entered;
    const first = f.dispatchRuntime.close();
    const second = f.dispatchRuntime.close();
    assert.equal(first, second);
    let secondSettled = false;
    second.finally(() => { secondSettled = true; });
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(secondSettled, false);
    finishExecution();
    await assert.rejects(active, {code: 'RemoteDispatchRuntimeClosed'});
    assert.deepEqual(await Promise.all([first, second]), [true, true]);
    assert.equal(closes, 1);
    assert.equal(await f.dispatchRuntime.close(), false);
  });

test('concurrent runtime closes report the same cleanup failure', async t => {
  let enteredExecution;
  const entered = new Promise(resolve => { enteredExecution = resolve; });
  let finishExecution;
  const executionGate = new Promise(resolve => { finishExecution = resolve; });
  const failure = new Error('physical close failed');
  let closes = 0;
  const f = await fixture(t, async () => {
    enteredExecution();
    await executionGate;
    return managedOutput({
      async close() {
        closes++;
        if (closes === 1) throw failure;
      },
    });
  }, {autoClose: false});
  const dispatch = request({dispatchId: 'concurrent-close-failure'});
  const record = f.store.accept(
    f.control.prepareAdmission(f.journal, dispatch), dispatch, f.control,
  );
  const active = f.dispatchRuntime.start(dispatch, record, undefined, '{}');
  await entered;
  const first = f.dispatchRuntime.close();
  const second = f.dispatchRuntime.close();
  assert.equal(first, second);
  finishExecution();
  await assert.rejects(active, error =>
    error instanceof AggregateError && error.errors.includes(failure),
  );
  const outcomes = await Promise.allSettled([first, second]);
  assert.equal(outcomes[0].status, 'rejected');
  assert.equal(outcomes[1].status, 'rejected');
  assert.equal(outcomes[0].reason, outcomes[1].reason);
  assert.equal(closes, 1);
  assert.equal(await f.dispatchRuntime.close(), true);
  assert.equal(closes, 2);
  assert.equal(await f.dispatchRuntime.close(), false);
});

test('failed physical reclaim remains owned and retryable', async t => {
  let closes = 0;
  const failure = new Error('close failed');
  const f = await fixture(t, async () => managedOutput({
    async close() {
      closes++;
      if (closes === 1) throw failure;
    },
  }));
  const dispatch = request();
  const record = f.store.accept(
    f.control.prepareAdmission(f.journal, dispatch),
    dispatch,
    f.control,
  );
  await f.dispatchRuntime.start(dispatch, record, undefined, '{}');
  await assert.rejects(
    f.dispatchRuntime.release(dispatch),
    error => error === failure,
  );
  assert.equal(closes, 1);
  assert.deepEqual(f.control.status(record), [3, 2, 3, 1, 0]);
  assert.deepEqual(
    runtime.siteControl.status(f.selectedSite).slice(2, 9),
    [0n, 0n, 1n, 0n, 8n, 0n, 0n],
  );
  assert.equal(await f.dispatchRuntime.release(dispatch), true);
  assert.equal(closes, 2);
  assert.deepEqual(f.control.status(record), [3, 2, 2, 0, 0]);
  assert.deepEqual(
    runtime.siteControl.status(f.selectedSite).slice(2, 9),
    [0n, 0n, 0n, 0n, 0n, 0n, 0n],
  );
});

test('invalid owned output is disposed once without admitting evidence',
  async t => {
    for (const [name, override] of [
      ['negative-rows', {rowCount: -1}],
      ['wrong-retained-type', {retainedBytes: 8}],
      ['extra-key', {unexpected: true}],
      ['invalid-measurement', {measurement: {rowCount: -1}}],
    ]) {
      let closes = 0;
      const f = await fixture(t, async () => managedOutput({
        ...override,
        async close() { closes++; },
      }));
      const dispatch = request({dispatchId: `invalid-output-${name}`});
      const record = f.store.accept(
        f.control.prepareAdmission(f.journal, dispatch), dispatch, f.control,
      );
      await assert.rejects(
        f.dispatchRuntime.start(dispatch, record, undefined, '{}'),
      );
      assert.equal(closes, 1, name);
      assert.equal(f.bundleHolds.size, 0, name);
      assert.deepEqual(
        runtime.siteControl.status(f.selectedSite).slice(2, 9),
        [0n, 0n, 0n, 0n, 0n, 0n, 0n],
        name,
      );
      assert.equal(await f.dispatchRuntime.cleanup(dispatch), false, name);
      assert.equal(closes, 1, name);
      assert.ok([0, 3].includes(f.control.status(record)[1]), name);
      assert.equal(f.control.status(record)[3], 0, name);
    }
  });

test('invalid output close failure keeps custody until retry', async t => {
  let closes = 0;
  const closeFailure = new Error('first disposal failed');
  const f = await fixture(t, async () => managedOutput({
    rowCount: -1,
    async close() {
      closes++;
      if (closes === 1) throw closeFailure;
    },
  }), {autoClose: false});
  const dispatch = request({dispatchId: 'invalid-output-retry'});
  const record = f.store.accept(
    f.control.prepareAdmission(f.journal, dispatch), dispatch, f.control,
  );
  await assert.rejects(
    f.dispatchRuntime.start(dispatch, record, undefined, '{}'),
    error => error instanceof AggregateError &&
      error.errors.some(child => child === closeFailure),
  );
  assert.equal(closes, 1);
  assert.equal(f.bundleHolds.size, 1);
  assert.equal(await f.dispatchRuntime.cleanup(dispatch), true);
  assert.equal(closes, 2);
  assert.equal(f.bundleHolds.size, 0);
  assert.equal(await f.dispatchRuntime.close(), true);
  assert.equal(closes, 2);
});

test('custody transition retry does not repeat a successful physical close',
  async t => {
    let closes = 0;
    let releaseCalls = 0;
    const f = await fixture(t, async () => managedOutput({
      rowCount: -1,
      async close() { closes++; },
    }), {
      autoClose: false,
      wrapControl: control => ({
        ...control,
        runtimeCustodyReleaseOutput(custody) {
          releaseCalls++;
          return releaseCalls === 1
            ? false
            : control.runtimeCustodyReleaseOutput(custody);
        },
      }),
    });
    const dispatch = request({dispatchId: 'invalid-output-custody-retry'});
    const record = f.store.accept(
      f.control.prepareAdmission(f.journal, dispatch),
      dispatch,
      f.control,
    );
    await assert.rejects(
      f.dispatchRuntime.start(dispatch, record, undefined, '{}'),
      error => error instanceof AggregateError &&
        error.errors.some(child =>
          child.code === 'RemoteRuntimeCustodyTransitionRejected'),
    );
    assert.equal(closes, 1);
    assert.equal(f.bundleHolds.size, 1);
    assert.equal(await f.dispatchRuntime.cleanup(dispatch), true);
    assert.equal(closes, 1);
    assert.equal(releaseCalls, 2);
    assert.equal(f.bundleHolds.size, 0);
    assert.equal(await f.dispatchRuntime.close(), true);
  });

test('output without disposal remains explicitly cleanup pending', async t => {
  const f = await fixture(t, async () => ({rowCount: -1}), {
    autoClose: false,
  });
  const dispatch = request({dispatchId: 'invalid-output-no-close'});
  const record = f.store.accept(
    f.control.prepareAdmission(f.journal, dispatch), dispatch, f.control,
  );
  await assert.rejects(
    f.dispatchRuntime.start(dispatch, record, undefined, '{}'),
    error => error.code === 'InvalidRemoteExecutionOutput' &&
      error.cleanupPending === true,
  );
  await assert.rejects(
    f.dispatchRuntime.close(),
    error => error.code === 'RemoteRuntimeCleanupPending' &&
      error.cleanupHandle.status().pending === true,
  );
  assert.equal(f.bundleHolds.size, 1);
});

test('untyped executor failures cannot confirm physical stop',
  async t => {
    for (const [name, primary] of [
      ['frozen', Object.freeze(new Error('frozen executor failure'))],
      ['primitive', 0],
    ]) {
      const f = await fixture(t, async () => { throw primary; }, {
        autoClose: false,
      });
      const dispatch = request({dispatchId: `executor-${name}`});
      const record = f.store.accept(
        f.control.prepareAdmission(f.journal, dispatch),
        dispatch,
        f.control,
      );
      await assert.rejects(
        f.dispatchRuntime.start(dispatch, record, undefined, '{}'),
        error => error === primary ||
          error instanceof AggregateError && error.errors.includes(primary),
      );
      assert.equal(f.bundleHolds.size, 1, name);
      assert.equal(await f.dispatchRuntime.cleanup(dispatch), false, name);
      await assert.rejects(f.dispatchRuntime.close(), error =>
        error.code === 'RemoteRuntimeCleanupPending' &&
        error.cleanupHandle.status().pending === true,
      );
    }
  });

test('concurrent release and close share one physical cleanup attempt',
  async t => {
    let closes = 0;
    let finishClose;
    const closeGate = new Promise(resolve => { finishClose = resolve; });
    const f = await fixture(t, async () => managedOutput({
      async close() {
        closes++;
        await closeGate;
      },
    }), {autoClose: false});
    const dispatch = request({dispatchId: 'single-flight-release'});
    const record = f.store.accept(
      f.control.prepareAdmission(f.journal, dispatch),
      dispatch,
      f.control,
    );
    await f.dispatchRuntime.start(dispatch, record, undefined, '{}');

    const first = f.dispatchRuntime.release(dispatch);
    const second = f.dispatchRuntime.release(dispatch);
    const closing = f.dispatchRuntime.close();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(closes, 1);
    finishClose();
    assert.deepEqual(await Promise.all([first, second, closing]), [true, true, true]);
    assert.equal(closes, 1);
  });

test('failed cleanup is retried once when release races runtime close',
  async t => {
    let closes = 0;
    let finishRetry;
    const retryGate = new Promise(resolve => { finishRetry = resolve; });
    const failure = new Error('first close failed');
    const f = await fixture(t, async () => managedOutput({
      async close() {
        closes++;
        if (closes === 1) throw failure;
        await retryGate;
      },
    }), {autoClose: false});
    const dispatch = request({dispatchId: 'single-flight-retry'});
    const record = f.store.accept(
      f.control.prepareAdmission(f.journal, dispatch),
      dispatch,
      f.control,
    );
    await f.dispatchRuntime.start(dispatch, record, undefined, '{}');
    await assert.rejects(f.dispatchRuntime.release(dispatch), error =>
      error === failure,
    );

    const retry = f.dispatchRuntime.release(dispatch);
    const closing = f.dispatchRuntime.close();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(closes, 2);
    finishRetry();
    assert.deepEqual(await Promise.all([retry, closing]), [true, true]);
    assert.equal(closes, 2);
  });

test('pending cleanup retry and close share one stop observation', async t => {
  let stopped = false;
  let retries = 0;
  let finishRetry;
  const retryGate = new Promise(resolve => { finishRetry = resolve; });
  const cleanupHandle = Object.freeze({
    status: () => Object.freeze({pending: !stopped, errors: []}),
    async retry() {
      retries++;
      await retryGate;
      stopped = true;
      return this.status();
    },
  });
  const failure = Object.assign(new Error('stop pending'), {
    cleanupPending: true,
    cleanupHandle,
  });
  const f = await fixture(
    t,
    async () => { throw failure; },
    {autoClose: false},
  );
  const dispatch = request({dispatchId: 'cleanup-close-single-flight'});
  const record = f.store.accept(
    f.control.prepareAdmission(f.journal, dispatch),
    dispatch,
    f.control,
  );
  await assert.rejects(
    f.dispatchRuntime.start(dispatch, record, undefined, '{}'),
    error => error === failure,
  );

  const cleanup = f.dispatchRuntime.cleanup(dispatch);
  const closing = f.dispatchRuntime.close();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(retries, 1);
  finishRetry();
  assert.deepEqual(await Promise.all([cleanup, closing]), [true, true]);
  assert.equal(retries, 1);
  assert.deepEqual(f.control.status(record), [4, 0, 2, 0, 0]);
});

test('unsupported grant is rejected before durable admission or execution',
  async t => {
    let executions = 0;
    const f = await fixture(t, async () => {
      executions++;
      throw new Error('must not execute');
    });
    const dispatch = request({grantCid: cid('5')});
    assert.equal(f.dispatchRuntime.supports(dispatch), false);
    assert.equal(f.store.inspect(dispatch, f.control), undefined);
    assert.equal(executions, 0);
  });

test('unregistered evidence issuer is rejected before admission or execution',
  async t => {
    let executions = 0;
    const f = await fixture(t, async () => {
      executions++;
      throw new Error('must not execute');
    });
    const dispatch = request({evidenceIssuerCapabilityCid: cid('d')});
    assert.equal(f.dispatchRuntime.supports(dispatch), false);
    assert.equal(f.store.inspect(dispatch, f.control), undefined);
    assert.equal(executions, 0);
  });

test('unprovisioned budget is rejected before durable admission', async t => {
  let executions = 0;
  const f = await fixture(t, async () => {
    executions++;
    throw new Error('must not execute');
  });
  const dispatch = request({budgetCid: cid('3')});
  assert.equal(f.dispatchRuntime.supports(dispatch), false);
  assert.equal(f.store.inspect(dispatch, f.control), undefined);
  assert.equal(executions, 0);
});

test('revoked Site is rejected before remote execution starts', async t => {
  let executions = 0;
  const f = await fixture(t, async () => {
    executions++;
    return managedOutput();
  });
  const dispatch = request();
  const record = f.store.accept(
    f.control.prepareAdmission(f.journal, dispatch),
    dispatch,
    f.control,
  );
  runtime.siteControl.revoke(f.selectedSite);
  assert.equal(f.dispatchRuntime.supports(dispatch), false);
  assert.throws(
    () => f.dispatchRuntime.start(dispatch, record, undefined, '{}'),
    {code: 'RemoteSiteUnavailable'},
  );
  assert.equal(executions, 0);
  assert.deepEqual(f.control.status(record), [0, 0, 0, 0, 0]);
});

test('Site revocation during execution cannot issue completion evidence',
  async t => {
    let executionStarted;
    let finishExecution;
    let closes = 0;
    const started = new Promise(resolve => { executionStarted = resolve; });
    const executing = new Promise(resolve => { finishExecution = resolve; });
    const f = await fixture(t, async () => {
      executionStarted();
      await executing;
      return managedOutput({async close() { closes++; }});
    });
    const dispatch = request();
    const record = f.store.accept(
      f.control.prepareAdmission(f.journal, dispatch),
      dispatch,
      f.control,
    );
    const operation = f.dispatchRuntime.start(
      dispatch,
      record,
      undefined,
      '{}',
    );
    await started;
    runtime.siteControl.revoke(f.selectedSite);
    finishExecution();
    await assert.rejects(operation, {code: 'RemoteSiteOperationUnavailable'});
    assert.equal(closes, 1);
    assert.equal(f.store.inspectEvidence(dispatch, f.control), undefined);
    assert.deepEqual(f.control.status(record), [4, 0, 2, 0, 0]);
  });

test('runtime rejects a record from a different dispatch occurrence',
  async t => {
    let executions = 0;
    const f = await fixture(t, async () => {
      executions++;
      throw new Error('must not execute');
    });
    const expected = request();
    const foreign = request({dispatchId: 'dispatch-b', taskAttempt: 2});
    const foreignRecord = f.store.accept(
      f.control.prepareAdmission(f.journal, foreign),
      foreign,
      f.control,
    );
    assert.throws(
      () => f.dispatchRuntime.start(expected, foreignRecord, undefined, '{}'),
      {code: 'RemoteDispatchRecordMismatch'},
    );
    assert.equal(executions, 0);
    assert.deepEqual(f.control.status(foreignRecord), [0, 0, 0, 0, 0]);
  });

test('runtime rejects a mismatched input binding before execution', async t => {
  let executions = 0;
  const f = await fixture(t, async () => {
    executions++;
    throw new Error('must not execute');
  });
  const dispatch = request();
  const record = f.store.accept(
    f.control.prepareAdmission(f.journal, dispatch),
    dispatch,
    f.control,
  );
  assert.throws(
    () => f.dispatchRuntime.start(
      dispatch,
      record,
      undefined,
      '{"changed":true}',
    ),
    {code: 'RemoteInputBindingMismatch'},
  );
  assert.equal(executions, 0);
  assert.deepEqual(f.control.status(record), [0, 0, 0, 0, 0]);
});

test('executor failure is durably failed without completion evidence',
  async t => {
    const failure = Object.assign(new Error('executor failed'), {
      cleanupHandle: Object.freeze({
        status: () => Object.freeze({pending: false}),
      }),
    });
    const f = await fixture(t, async () => { throw failure; });
    const dispatch = request();
    const record = f.store.accept(
      f.control.prepareAdmission(f.journal, dispatch),
      dispatch,
      f.control,
    );
    await assert.rejects(
      f.dispatchRuntime.start(dispatch, record, undefined, '{}'),
      error => error === failure,
    );
    assert.deepEqual(f.control.status(record), [4, 0, 2, 0, 0]);
    assert.equal(f.store.inspectEvidence(dispatch, f.control), undefined);
  });

test('output above retained reservation fails and releases Site capacity',
  async t => {
    let closes = 0;
    const f = await fixture(t, async () => managedOutput({
      materialGeneration: 'oversized-material',
      retainedBytes: 65n,
      async close() { closes++; },
    }));
    const dispatch = request();
    const record = f.store.accept(
      f.control.prepareAdmission(f.journal, dispatch),
      dispatch,
      f.control,
    );
    await assert.rejects(
      f.dispatchRuntime.start(dispatch, record, undefined, '{}'),
      {code: 'RemoteSiteHoldingRejected'},
    );
    assert.equal(closes, 1);
    assert.deepEqual(f.control.status(record), [4, 0, 2, 0, 0]);
    assert.deepEqual(
      runtime.siteControl.status(f.selectedSite).slice(2, 9),
      [0n, 0n, 0n, 0n, 0n, 0n, 0n],
    );
  });

test('cancellation retains Site capacity until executor stop is observed',
  async t => {
    let enteredResolve;
    let stopResolve;
    const entered = new Promise(resolve => { enteredResolve = resolve; });
    const stopped = new Promise(resolve => { stopResolve = resolve; });
    const f = await fixture(t, async ({signal}) => {
      enteredResolve();
      await new Promise((resolve, reject) => {
        signal.addEventListener('abort', async () => {
          await stopped;
          reject(Object.assign(new Error('RemoteDispatchCancelled'), {
            code: 'RemoteDispatchCancelled',
            cleanupHandle: Object.freeze({
              status: () => Object.freeze({pending: false}),
            }),
          }));
        }, {once: true});
      });
    });
    const dispatch = request();
    const record = f.store.accept(
      f.control.prepareAdmission(f.journal, dispatch),
      dispatch,
      f.control,
    );
    const operation = f.dispatchRuntime.start(
      dispatch,
      record,
      undefined,
      '{}',
    );
    await entered;
    assert.equal(f.dispatchRuntime.cancel(dispatch), true);
    assert.deepEqual(f.control.status(record), [2, 0, 0, 0, 0]);
    assert.deepEqual(
      runtime.siteControl.status(f.selectedSite).slice(2, 9),
      [1n, 0n, 0n, 0n, 0n, 64n, 16n],
    );
    stopResolve();
    await assert.rejects(operation, {code: 'RemoteDispatchCancelled'});
    assert.deepEqual(f.control.status(record), [5, 0, 2, 0, 0]);
    assert.deepEqual(
      runtime.siteControl.status(f.selectedSite).slice(2, 9),
      [0n, 0n, 0n, 0n, 0n, 0n, 0n],
    );
  });

test('unconfirmed executor stop retains cleanup until retry confirms it',
  async t => {
    let stopped = false;
    let retries = 0;
    const cleanupHandle = Object.freeze({
      status: () => Object.freeze({pending: !stopped}),
      async retry() { retries++; stopped = true; return this.status(); },
    });
    const failure = Object.assign(new Error('stop pending'), {
      cleanupPending: true,
      cleanupHandle,
    });
    const f = await fixture(t, async () => { throw failure; });
    const dispatch = request();
    const record = f.store.accept(
      f.control.prepareAdmission(f.journal, dispatch),
      dispatch,
      f.control,
    );
    await assert.rejects(
      f.dispatchRuntime.start(dispatch, record, undefined, '{}'),
      error => error === failure,
    );
    assert.deepEqual(f.control.status(record), [6, 0, 3, 0, 0]);
    assert.deepEqual(
      runtime.siteControl.status(f.selectedSite).slice(2, 9),
      [1n, 0n, 0n, 0n, 0n, 64n, 16n],
    );
    assert.equal(f.bundleHolds.size, 1);
    assert.equal(await f.dispatchRuntime.cleanup(dispatch), true);
    assert.equal(retries, 1);
    assert.equal(f.bundleHolds.size, 0);
    assert.deepEqual(f.control.status(record), [4, 0, 2, 0, 0]);
    assert.deepEqual(
      runtime.siteControl.status(f.selectedSite).slice(2, 9),
      [0n, 0n, 0n, 0n, 0n, 0n, 0n],
    );
  });

test('cancelled unknown execution reconciles as cancellation after stop',
  async t => {
    const controller = new AbortController();
    let stopped = false;
    const cleanupHandle = Object.freeze({
      status: () => Object.freeze({pending: !stopped}),
      async retry() { stopped = true; return this.status(); },
    });
    const failure = Object.assign(new Error('cancel pending'), {
      cleanupPending: true,
      cleanupHandle,
    });
    const f = await fixture(t, async () => {
      controller.abort();
      throw failure;
    });
    const dispatch = request();
    const record = f.store.accept(
      f.control.prepareAdmission(f.journal, dispatch),
      dispatch,
      f.control,
    );
    await assert.rejects(
      f.dispatchRuntime.start(dispatch, record, controller.signal, '{}'),
      error => error === failure,
    );
    assert.deepEqual(f.control.status(record), [6, 0, 3, 0, 0]);
    assert.equal(await f.dispatchRuntime.cleanup(dispatch), true);
    assert.deepEqual(f.control.status(record), [5, 0, 2, 0, 0]);
  });

test('cleanup status errors remain unknown until a later observation',
  async t => {
    let statusMode = 'throws';
    const statusFailure = new Error('status unavailable');
    const cleanupHandle = Object.freeze({
      status() {
        if (statusMode === 'throws') throw statusFailure;
        if (statusMode === 'malformed') return {pending: 'unknown'};
        return Object.freeze({pending: false});
      },
    });
    const failure = Object.assign(new Error('stop unknown'), {
      cleanupPending: true,
      cleanupHandle,
    });
    const f = await fixture(t, async () => { throw failure; });
    const dispatch = request();
    const record = f.store.accept(
      f.control.prepareAdmission(f.journal, dispatch),
      dispatch,
      f.control,
    );
    await assert.rejects(
      f.dispatchRuntime.start(dispatch, record, undefined, '{}'),
    );
    assert.equal(await f.dispatchRuntime.cleanup(dispatch), false);
    assert.deepEqual(f.control.status(record), [6, 0, 3, 0, 0]);
    statusMode = 'malformed';
    assert.equal(await f.dispatchRuntime.cleanup(dispatch), false);
    assert.deepEqual(f.control.status(record), [6, 0, 3, 0, 0]);
    statusMode = 'stopped';
    assert.equal(await f.dispatchRuntime.cleanup(dispatch), true);
    assert.deepEqual(f.control.status(record), [4, 0, 2, 0, 0]);
  });

test('missing cleanup authority keeps runtime close explicitly pending',
  async t => {
    const failure = Object.assign(new Error('authority missing'), {
      cleanupPending: true,
    });
    const f = await fixture(
      t,
      async () => { throw failure; },
      {autoClose: false},
    );
    const dispatch = request();
    const record = f.store.accept(
      f.control.prepareAdmission(f.journal, dispatch),
      dispatch,
      f.control,
    );
    await assert.rejects(
      f.dispatchRuntime.start(dispatch, record, undefined, '{}'),
    );
    await assert.rejects(
      f.dispatchRuntime.close(),
      error => error.code === 'RemoteRuntimeCleanupPending' &&
        error.cleanupPending === true &&
        error.cleanupHandle.status().pending === true,
    );
    assert.deepEqual(f.control.status(record), [6, 0, 3, 0, 0]);
  });

test('failure journal errors retain delayed native cleanup ownership',
  async t => {
    for (const commitBeforeFailure of [false, true]) {
      let stopPending = true;
      let retries = 0;
      let advances = 0;
      const nativeFailure = Object.assign(new Error('native pending'), {
        cleanupPending: true,
        cleanupHandle: Object.freeze({
          status: () => Object.freeze({pending: stopPending, errors: []}),
          async retry() {
            retries++;
            stopPending = false;
          },
        }),
      });
      const persistenceFailure = new Error('injected failure journal EIO');
      const f = await fixture(t, async () => { throw nativeFailure; }, {
        autoClose: false,
        wrapStore: store => ({
          ...store,
          advance(...arguments_) {
            advances++;
            if (advances !== 3) return store.advance(...arguments_);
            if (commitBeforeFailure) store.advance(...arguments_);
            throw persistenceFailure;
          },
        }),
      });
      const dispatch = request({
        dispatchId: `journal-${commitBeforeFailure}`,
        taskAttempt: commitBeforeFailure ? 3 : 2,
      });
      const record = f.store.accept(
        f.control.prepareAdmission(f.journal, dispatch),
        dispatch,
        f.control,
      );
      await assert.rejects(
        f.dispatchRuntime.start(dispatch, record, undefined, '{}'),
        error => error instanceof AggregateError &&
          error.errors[0] === nativeFailure &&
          error.errors[1] === persistenceFailure,
      );
      assert.equal(stopPending, true);
      assert.equal(await f.dispatchRuntime.cleanup(dispatch), true);
      assert.equal(retries, 1);
      assert.equal(stopPending, false);
      assert.equal(await f.dispatchRuntime.close(), true);
    }
  });

test('output and holding survive failure journal errors until cleanup',
  async t => {
    let closes = 0;
    let advances = 0;
    const primary = new Error('retained transition failed');
    const persistenceFailure = new Error('failure transition failed');
    const f = await fixture(t, async () => managedOutput({
      async close() { closes++; },
    }), {
      autoClose: false,
      wrapStore: store => ({
        ...store,
        advance(...arguments_) {
          advances++;
          if (advances === 4) throw primary;
          if (advances === 5) throw persistenceFailure;
          return store.advance(...arguments_);
        },
      }),
    });
    const dispatch = request({dispatchId: 'output-journal-failure'});
    const record = f.store.accept(
      f.control.prepareAdmission(f.journal, dispatch),
      dispatch,
      f.control,
    );
    await assert.rejects(
      f.dispatchRuntime.start(dispatch, record, undefined, '{}'),
      error => error instanceof AggregateError &&
        error.errors[0] === primary &&
        error.errors[1] === persistenceFailure,
    );
    assert.equal(closes, 0);
    assert.deepEqual(
      runtime.siteControl.status(f.selectedSite).slice(2, 9),
      [0n, 0n, 1n, 0n, 8n, 0n, 0n],
    );
    assert.equal(await f.dispatchRuntime.cleanup(dispatch), true);
    assert.equal(closes, 1);
    assert.deepEqual(
      runtime.siteControl.status(f.selectedSite).slice(2, 9),
      [0n, 0n, 0n, 0n, 0n, 0n, 0n],
    );
    assert.equal(await f.dispatchRuntime.close(), true);
  });
