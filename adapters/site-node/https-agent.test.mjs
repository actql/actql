import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {startHttpsRemoteSiteAgent} from './https-agent.mjs';
import {
  cancelRemoteDispatch,
  queryRemoteDispatch,
  sendRemoteDispatch,
} from
  '../host-node/remote-site-client.mjs';
import {createRemoteSiteCoordinator} from
  '../host-node/remote-site-coordinator.mjs';
import {openSqliteCoordinatorDispatchJournal} from
  '../host-node/sqlite-coordinator-journal.mjs';
import {allowAllAuthorization} from '../host-node/authorization-fixture.mjs';
import {
  certificates,
  startFixture,
  terminalStatus,
} from './https-agent-harness.mjs';

// Run-owner account for these transport tests: dispatch and egress are
// explicitly allowed; authorization outcomes are covered elsewhere.
const remoteAuthorization = await allowAllAuthorization();

const cid = digit => `sha256:${digit.repeat(64)}`;
const runtime = runtimeCore(moon);

test('mTLS subprocess durably reconciles exact dispatch retransmission',
  async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-remote-https-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const material = await certificates(root);
    const fixture = await startFixture(root, material);
    t.after(() => fixture.close());
    const coordinatorStore = openSqliteCoordinatorDispatchJournal(
      join(root, 'coordinator'),
      {coordinatorAuthority: 'coordinator-a'},
    );
    t.after(() => coordinatorStore.close());
    const coordinator = createRemoteSiteCoordinator({
      authorization: remoteAuthorization,
      control: runtime.remoteSiteControl,
      journal: runtime.remoteSiteControl.createCoordinatorJournal(
        'coordinator-a',
      ),
      store: coordinatorStore,
    });
    const request = fixture.dispatch();
    const options = {
      origin: fixture.origin,
      ca: material.ca,
      cert: material.coordinatorCertificate,
      key: material.coordinatorKey,
      control: runtime.remoteSiteControl,
      dispatch: request,
      inputBindingBody: '{}',
    };
    const first = await coordinator.dispatch(options);
    assert.equal(first.dispatchRequestCid, runtime.remoteSiteControl.identity(request));
    assert.equal(
      coordinator.completionEvidenceAvailable(options),
      false,
    );
    const completed = await terminalStatus(
      options,
      value => coordinator.query(value),
    );
    assert.deepEqual(completed.state, [3, 2, 0, 1, 0]);
    assert.equal(completed.revision, 5);
    assert.equal(typeof completed.evidenceWire, 'string');
    assert.equal(typeof completed.measurementWire, 'string');
    assert.equal(
      runtime.remoteSiteControl.evidenceIdentity(completed.evidence),
      completed.evidenceCid,
    );
    assert.equal(
      runtime.remoteSiteControl.managedOutputMeasurementIdentity(
        completed.measurement,
      ),
      completed.measurementCid,
    );
    assert.equal(
      JSON.parse(completed.evidenceWire).dispatch_request_cid,
      first.dispatchRequestCid,
    );
    assert.equal(
      coordinator.completionEvidenceAvailable(options),
      true,
    );
    const retransmitted = await coordinator.dispatch(options);
    assert.deepEqual(retransmitted.state, completed.state);
    assert.equal(retransmitted.revision, completed.revision);

    const released = await coordinator.release(options);
    assert.deepEqual(released.state, [3, 2, 2, 0, 0]);
    assert.equal(released.revision, 7);
    assert.equal(
      coordinator.completionEvidenceAvailable(options),
      false,
    );
    const releasedAgain = await coordinator.release(options);
    assert.deepEqual(releasedAgain.state, released.state);
    assert.equal(releasedAgain.revision, released.revision);

    await assert.rejects(
      sendRemoteDispatch({
        ...options,
        dispatch: fixture.dispatch('dispatch-a', 'local/2'),
      }),
      error => error.code === 'RemoteSiteRejected' && error.status === 409,
    );
    await assert.rejects(
      sendRemoteDispatch({
        ...options,
        cert: material.foreignCertificate,
        key: material.foreignKey,
      }),
      error => error.code === 'RemoteSiteRejected' && error.status === 404,
    );
    await assert.rejects(
      sendRemoteDispatch({
        ...options,
        dispatch: fixture.dispatch(
          'dispatch-wrong-bundle',
          'local/1',
          {runtimeBundleCid: cid('a'), taskAttempt: 2},
        ),
      }),
      error => error.code === 'RemoteSiteRejected' && error.status === 400,
    );
    coordinatorStore.close();
    const reopenedStore = openSqliteCoordinatorDispatchJournal(
      join(root, 'coordinator'),
      {coordinatorAuthority: 'coordinator-a'},
    );
    t.after(() => reopenedStore.close());
    const reopened = createRemoteSiteCoordinator({
      authorization: remoteAuthorization,
      control: runtime.remoteSiteControl,
      journal: runtime.remoteSiteControl.createCoordinatorJournal(
        'coordinator-a',
      ),
      store: reopenedStore,
    });
    assert.equal(reopened.recovered.length, 1);
    assert.equal(reopened.completionEvidenceAvailable(options), false);
    const reopenedEvidence = reopenedStore.inspectEvidence(
      request,
      runtime.remoteSiteControl,
    );
    assert.equal(reopenedEvidence.evidenceCid, completed.evidenceCid);
    assert.equal(
      reopenedEvidence.measurementCid,
      completed.measurementCid,
    );
  });

test('exact retransmission bypasses new-work capacity and admission closure',
  async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-remote-retransmit-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const material = await certificates(root);
    const fixture = await startFixture(root, material, {
      delayMs: 10_000,
      maxConcurrentOperations: 1,
    });
    t.after(() => fixture.close());
    const request = fixture.dispatch('dispatch-retransmit');
    const options = {
      origin: fixture.origin,
      ca: material.ca,
      cert: material.coordinatorCertificate,
      key: material.coordinatorKey,
      control: runtime.remoteSiteControl,
      dispatch: request,
      inputBindingBody: '{}',
    };
    await sendRemoteDispatch(options);
    for (let attempt = 0; attempt < 100 && fixture.executionStarts() === 0;
      attempt++) {
      await new Promise(resolve => setTimeout(resolve, 5));
    }
    assert.equal(fixture.executionStarts(), 1);
    assert.equal(await fixture.stopAdmission(), true);

    const replayed = await sendRemoteDispatch(options);
    assert.equal(
      replayed.dispatchRequestCid,
      runtime.remoteSiteControl.identity(request),
    );
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.equal(fixture.executionStarts(), 1);
    await assert.rejects(
      sendRemoteDispatch({
        ...options,
        dispatch: fixture.dispatch(
          'dispatch-new',
          'local/1',
          {taskAttempt: 2},
        ),
      }),
      error => error.code === 'RemoteSiteRejected' && error.status === 503,
    );

    await cancelRemoteDispatch(options);
    const terminal = await terminalStatus(options);
    assert.deepEqual(terminal.state, [5, 0, 2, 0, 0]);
  });

test('authenticated cancellation waits for physical handler exit', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-remote-cancel-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const material = await certificates(root);
  const fixture = await startFixture(root, material, {delayMs: 10_000});
  t.after(() => fixture.close());
  const request = fixture.dispatch('dispatch-cancel');
  const options = {
    origin: fixture.origin,
    ca: material.ca,
    cert: material.coordinatorCertificate,
    key: material.coordinatorKey,
    control: runtime.remoteSiteControl,
    dispatch: request,
    inputBindingBody: '{}',
  };
  await sendRemoteDispatch(options);
  await assert.rejects(
    cancelRemoteDispatch({
      ...options,
      cert: material.foreignCertificate,
      key: material.foreignKey,
    }),
    error => error.code === 'RemoteSiteRejected' && error.status === 404,
  );
  assert.deepEqual((await queryRemoteDispatch(options)).state, [2, 0, 0, 0, 0]);
  const cancellation = await cancelRemoteDispatch(options);
  assert.equal(
    cancellation.dispatchRequestCid,
    runtime.remoteSiteControl.identity(request),
  );
  const terminal = await terminalStatus(options);
  assert.deepEqual(terminal.state, [5, 0, 2, 0, 0]);
  assert.equal(terminal.evidence, undefined);
});

test('mTLS resend starts a durably accepted but unstarted dispatch once',
  async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-remote-preaccepted-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const material = await certificates(root);
    const fixture = await startFixture(root, material, {
      preacceptDispatchId: 'dispatch-preaccepted',
    });
    t.after(() => fixture.close());
    const options = {
      origin: fixture.origin,
      ca: material.ca,
      cert: material.coordinatorCertificate,
      key: material.coordinatorKey,
      control: runtime.remoteSiteControl,
      dispatch: fixture.dispatch('dispatch-preaccepted'),
      inputBindingBody: '{}',
    };
    assert.deepEqual((await queryRemoteDispatch(options)).state,
      [0, 0, 0, 0, 0]);
    assert.equal(fixture.executionStarts(), 0);
    const first = await sendRemoteDispatch(options);
    assert.equal(first.dispatchRequestCid,
      runtime.remoteSiteControl.identity(options.dispatch));
    assert.deepEqual((await terminalStatus(options)).state,
      [3, 2, 0, 1, 0]);
    assert.equal(fixture.executionStarts(), 1);
    await sendRemoteDispatch(options);
    assert.equal(fixture.executionStarts(), 1);
  });

test('Agent close retries runtime cleanup without reopening admission',
  async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-remote-close-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const material = await certificates(root);
    let closes = 0;
    const pending = Object.assign(new Error('cleanup pending'), {
      cleanupPending: true,
    });
    const agent = await startHttpsRemoteSiteAgent({
      key: material.siteKey,
      cert: material.siteCertificate,
      ca: material.ca,
      coordinatorAuthorities: new Map(),
      siteKey: 'site-a',
      siteGeneration: 1,
      journal: {},
      store: {},
      control: {
        runtimeStartable: () => false,
        admitPollDispatch() {},
        pollDispatchRequest() {},
        pollDispatchBindingBody() {},
      },
      admitDispatchJson() {},
      dispatchRuntime: {
        supports: () => false,
        start() {},
        cancel() {},
        release() {},
        async close() {
          closes++;
          if (closes === 1) throw pending;
          return true;
        },
      },
    });
    await assert.rejects(agent.close(), error => error === pending);
    assert.equal(closes, 1);
    assert.equal(await agent.close(), true);
    assert.equal(closes, 2);
    assert.equal(await agent.close(), false);
    assert.equal(closes, 2);
  });

test('concurrent Agent close calls share one runtime cleanup attempt',
  async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-remote-close-race-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const material = await certificates(root);
    let finishClose;
    let closes = 0;
    const closeGate = new Promise(resolve => { finishClose = resolve; });
    const agent = await startHttpsRemoteSiteAgent({
      key: material.siteKey,
      cert: material.siteCertificate,
      ca: material.ca,
      coordinatorAuthorities: new Map(),
      siteKey: 'site-a',
      siteGeneration: 1,
      journal: {},
      store: {},
      control: {
        runtimeStartable: () => false,
        admitPollDispatch() {},
        pollDispatchRequest() {},
        pollDispatchBindingBody() {},
      },
      admitDispatchJson() {},
      dispatchRuntime: {
        supports: () => false,
        start() {},
        cancel() {},
        release() {},
        async close() {
          closes++;
          await closeGate;
          return true;
        },
      },
    });
    const first = agent.close();
    const second = agent.close();
    finishClose();
    assert.deepEqual(await Promise.all([first, second]), [true, true]);
    assert.equal(closes, 1);
    assert.equal(await agent.close(), false);
  });
