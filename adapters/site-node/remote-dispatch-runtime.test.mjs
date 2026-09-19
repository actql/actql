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
    inputBindingCid: cid('1'),
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
    holdingEvidenceCid: cid('c'),
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
  {autoClose = true, wrapStore = value => value} = {},
) {
  const root = await mkdtemp(join(tmpdir(), 'actql-remote-runtime-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const selectedSite = site();
  const control = runtime.remoteSiteControl;
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
  const dispatchRuntime = createRemoteDispatchRuntime({
    control,
    siteControl: runtime.siteControl,
    store: wrapStore(store),
    registrations: [registration],
    budgets: [dispatchBudget],
  });
  t.after(async () => {
    if (autoClose) await dispatchRuntime.close();
    store.close();
  });
  return {control, dispatchRuntime, journal, root, selectedSite, store};
}

test('registered runtime durably executes, evidences, and releases output',
  async t => {
    let executions = 0;
    let closes = 0;
    const f = await fixture(t, async () => {
      executions++;
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
    const completed = await f.dispatchRuntime.start(dispatch, record);
    assert.equal(executions, 1);
    assert.deepEqual(completed.state, [3, 2, 0, 1, 0]);
    assert.equal(completed.revision, 5);
    assert.equal(
      f.store.inspectEvidence(dispatch, f.control).execution_evidence_cid,
      f.control.evidenceIdentity(completed.evidence),
    );
    assert.throws(
      () => f.dispatchRuntime.start(dispatch, record),
      {code: 'RemoteDispatchAlreadyStarted'},
    );
    assert.deepEqual(
      runtime.siteControl.status(f.selectedSite).slice(2, 9),
      [0n, 0n, 1n, 0n, 8n, 0n, 0n],
    );
    assert.equal(await f.dispatchRuntime.release(dispatch), true);
    assert.equal(closes, 1);
    assert.deepEqual(f.control.status(record), [3, 2, 2, 0, 0]);
    assert.deepEqual(
      runtime.siteControl.status(f.selectedSite).slice(2, 9),
      [0n, 0n, 0n, 0n, 0n, 0n, 0n],
    );
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
  await f.dispatchRuntime.start(dispatch, record);
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
    () => f.dispatchRuntime.start(dispatch, record),
    {code: 'RemoteSiteUnavailable'},
  );
  assert.equal(executions, 0);
  assert.deepEqual(f.control.status(record), [0, 0, 0, 0, 0]);
});

test('Site revocation during execution cannot issue completion evidence',
  async t => {
    let finishExecution;
    let closes = 0;
    const executing = new Promise(resolve => { finishExecution = resolve; });
    const f = await fixture(t, async () => {
      await executing;
      return managedOutput({async close() { closes++; }});
    });
    const dispatch = request();
    const record = f.store.accept(
      f.control.prepareAdmission(f.journal, dispatch),
      dispatch,
      f.control,
    );
    const operation = f.dispatchRuntime.start(dispatch, record);
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
      () => f.dispatchRuntime.start(expected, foreignRecord),
      {code: 'RemoteDispatchRecordMismatch'},
    );
    assert.equal(executions, 0);
    assert.deepEqual(f.control.status(foreignRecord), [0, 0, 0, 0, 0]);
  });

test('executor failure is durably failed without completion evidence',
  async t => {
    const failure = new Error('executor failed');
    const f = await fixture(t, async () => { throw failure; });
    const dispatch = request();
    const record = f.store.accept(
      f.control.prepareAdmission(f.journal, dispatch),
      dispatch,
      f.control,
    );
    await assert.rejects(
      f.dispatchRuntime.start(dispatch, record),
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
      f.dispatchRuntime.start(dispatch, record),
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
          reject(signal.reason);
        }, {once: true});
      });
    });
    const dispatch = request();
    const record = f.store.accept(
      f.control.prepareAdmission(f.journal, dispatch),
      dispatch,
      f.control,
    );
    const operation = f.dispatchRuntime.start(dispatch, record);
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
      f.dispatchRuntime.start(dispatch, record),
      error => error === failure,
    );
    assert.deepEqual(f.control.status(record), [6, 0, 3, 0, 0]);
    assert.deepEqual(
      runtime.siteControl.status(f.selectedSite).slice(2, 9),
      [1n, 0n, 0n, 0n, 0n, 64n, 16n],
    );
    assert.equal(await f.dispatchRuntime.cleanup(dispatch), true);
    assert.equal(retries, 1);
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
      f.dispatchRuntime.start(dispatch, record, controller.signal),
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
    await assert.rejects(f.dispatchRuntime.start(dispatch, record));
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
    await assert.rejects(f.dispatchRuntime.start(dispatch, record));
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
        f.dispatchRuntime.start(dispatch, record),
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
      f.dispatchRuntime.start(dispatch, record),
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
