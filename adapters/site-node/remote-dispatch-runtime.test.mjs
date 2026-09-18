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
    budgetCid: cid('3'),
    grantCid: cid('4'),
    ...overrides,
  }));
}

async function fixture(t, execute, {autoClose = true} = {}) {
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
    evidenceKind: 'actql.remote.physical-output/0.1',
    issuerCapabilityCid: cid('b'),
    execute,
  });
  const dispatchRuntime = createRemoteDispatchRuntime({
    control,
    store,
    registrations: [registration],
  });
  t.after(async () => {
    if (autoClose) await dispatchRuntime.close();
    store.close();
  });
  return {control, dispatchRuntime, journal, root, store};
}

test('registered runtime durably executes, evidences, and releases output',
  async t => {
    let executions = 0;
    let closes = 0;
    const f = await fixture(t, async () => {
      executions++;
      return Object.freeze({
        materialGeneration: 'material-generation-a',
        holdingEvidenceCid: cid('c'),
        evidenceSubjectCid: cid('d'),
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
    assert.equal(await f.dispatchRuntime.release(dispatch), true);
    assert.equal(closes, 1);
    assert.deepEqual(f.control.status(record), [3, 2, 2, 0, 0]);
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
    assert.deepEqual(f.control.status(record), [4, 0, 0, 0, 0]);
    assert.equal(f.store.inspectEvidence(dispatch, f.control), undefined);
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
    assert.equal(await f.dispatchRuntime.cleanup(dispatch), true);
    assert.equal(retries, 1);
    assert.deepEqual(f.control.status(record), [4, 0, 2, 0, 0]);
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
    let statusFails = true;
    const statusFailure = new Error('status unavailable');
    const cleanupHandle = Object.freeze({
      status() {
        if (statusFails) throw statusFailure;
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
    statusFails = false;
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
