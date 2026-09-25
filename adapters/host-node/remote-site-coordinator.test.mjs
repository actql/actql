import assert from 'node:assert/strict';
import {mkdir, mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openSqliteCoordinatorDispatchJournal} from
  './sqlite-coordinator-journal.mjs';
import {createRemoteSiteCoordinator} from './remote-site-coordinator.mjs';
import {
  FIXTURE_CONTEXT,
  accountEntry,
  allowAllAuthorization,
  fixtureAuthorization,
  sqliteDeferral,
} from './authorization-fixture.mjs';

const authorization = await allowAllAuthorization();

const cid = digit => `sha256:${digit.repeat(64)}`;
const runtime = runtimeCore(moon);
const control = runtime.remoteSiteControl;
const transferControl = runtime.remoteTransferControl;
const scratch = fileURLToPath(new URL('../../../actql-test-runs/', import.meta.url));
const request = dispatchId => control.prepare({
  coordinatorAuthority: 'coordinator-a',
  runDefinitionCid: cid('0'),
  taskKey: 'task-a',
  taskAttempt: 1,
  dispatchId,
  siteKey: 'site-a',
  siteGeneration: 1,
  runtimeBundleCid: cid('a'),
  connectorRegistration: 'local',
  connectorRevision: 'local/1',
  strategyRevision: 'strategy/1',
  inputBindingCid: cid('1'),
  obligationsCid: cid('2'),
  budgetCid: cid('3'),
  evidenceIssuerCapabilityCid: cid('b'),
  grantCid: cid('4'),
});

function outputFixture(dispatch, route = 'direct', overrides = {}) {
  const {
    sourceSite = 'site-a',
    sourceSiteGeneration = 1,
    materialGeneration = cid('e'),
    ...configurationOverrides
  } = overrides;
  const configuration = {
    storeAuthorityCid: cid('5'),
    publicationAttemptCid: cid('6'),
    resultDefinitionCid: cid('7'),
    orderingEvidenceCid: cid('8'),
    coordinatorAuthority: 'coordinator-a',
    transferAttemptId: 'transfer-coordinator-output',
    transferRoute: route,
    destinationSite: 'site-b',
    destinationSiteGeneration: 2,
    transferMaxBytes: 1024n,
    transferExpiresAtMilliseconds: 2_000_000_000_000n,
    sourceGrantCid: cid('9'),
    destinationGrantCid: cid('c'),
    routeCapabilityCid: cid('d'),
    transferOrigin: 'https://transfer.example.invalid/output',
    ...configurationOverrides,
  };
  const intent = control.prepareOutputIntent(dispatch, configuration);
  const manifest = {
    version: 'actql-managed-physical-manifest/0.1',
    schemaContractCid: cid('1'),
    viewContractCid: cid('2'),
    codecContractCid: cid('3'),
    rowCount: 2,
    chunks: [{cid: cid('a'), byteLength: 12n, rowCount: 2}],
  };
  const payloadRequest = control.preparePublicationPayload({
    storeAuthorityCid: configuration.storeAuthorityCid,
    publicationAttemptCid: configuration.publicationAttemptCid,
    materialGenerationCid: materialGeneration,
    resultDefinitionCid: configuration.resultDefinitionCid,
    logicalRelationCid: manifest.viewContractCid,
    resultSchemaCid: manifest.schemaContractCid,
    orderingEvidenceCid: configuration.orderingEvidenceCid,
    durableCodecCid: manifest.codecContractCid,
    maxBytes: 12n,
    rowCount: 2n,
  });
  const transferRequest = transferControl.prepare({
    coordinatorAuthority: 'coordinator-a',
    transferAttemptId: configuration.transferAttemptId,
    route,
    sourceSite,
    sourceSiteGeneration,
    destinationSite: configuration.destinationSite,
    destinationSiteGeneration: configuration.destinationSiteGeneration,
    sourceMaterialGeneration: materialGeneration,
    physicalManifest: manifest,
    limits: {
      maxChunks: 4,
      maxManifestBytes: 4096,
      maxReferencedBytes: 12n,
    },
    capacityBytes: configuration.transferMaxBytes,
    expiresAtMilliseconds: configuration.transferExpiresAtMilliseconds,
    sourceGrantCid: configuration.sourceGrantCid,
    destinationGrantCid: configuration.destinationGrantCid,
    routeCapabilityCid: configuration.routeCapabilityCid,
  });
  let transferRecord = transferControl.open(transferRequest);
  transferRecord = transferControl.commitTransition(
    transferControl.prepareStart(transferRecord),
    true,
  );
  transferRecord = transferControl.commitTransition(
    transferControl.prepareSourceSettled(
      transferRecord,
      true,
      route === 'store',
    ),
    true,
  );
  transferRecord = transferControl.commitTransition(
    transferControl.prepareDestinationCommit(transferRecord),
    true,
  );
  const output = control.admitPollOutput(
    control.pollOutputJson(dispatch, intent),
  );
  const result = control.prepareOutputResult(
    output,
    payloadRequest,
    cid('f'),
    transferRecord,
  );
  return Object.freeze({
    intent,
    payloadRequest,
    transferRequest,
    transferRecord,
    result,
  });
}

test('Coordinator makes exact intent durable before transport starts',
  async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-coordinator-client-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const store = openSqliteCoordinatorDispatchJournal(root, {
      coordinatorAuthority: 'coordinator-a',
    });
    t.after(() => store.close());
    const dispatch = request('dispatch-a');
    const calls = [];
    const coordinator = createRemoteSiteCoordinator({
      authorization,
      control,
      journal: control.createCoordinatorJournal('coordinator-a'),
      store,
      send: async options => {
        assert.equal(store.contains(options.dispatch, control), true);
        calls.push('send');
        throw Object.assign(new Error('ResponseLost'), {code: 'ResponseLost'});
      },
      query: async () => {
        calls.push('query');
        return Object.freeze({revision: 0, state: [0, 0, 0, 0, 0]});
      },
      cancel: async () => {
        calls.push('cancel');
        return Object.freeze({revision: 0, state: [0, 0, 0, 0, 0]});
      },
    });
    await assert.rejects(
      coordinator.dispatch({dispatch}),
      {code: 'ResponseLost'},
    );
    assert.equal(store.contains(dispatch, control), true);
    assert.deepEqual(store.inspectState(dispatch, control), [
      1, 1, -1, -1, -1, -1, false, false, '', '', '',
    ]);
    await assert.rejects(
      coordinator.dispatch({dispatch: request('dispatch-b')}),
      {code: 'MoonBitHostFailure'},
    );
    assert.deepEqual(calls, ['send']);
    await coordinator.query({dispatch});
    await coordinator.cancel({dispatch});
    assert.deepEqual(calls, ['send', 'query', 'cancel']);
    assert.deepEqual(store.inspectState(dispatch, control), [
      3, 2, 0, 0, 0, 0, false, false, '', '', '',
    ]);
    assert.equal(
      coordinator.completionEvidenceAvailable({dispatch}),
      false,
    );
    store.close();
    const reopenedStore = openSqliteCoordinatorDispatchJournal(root, {
      coordinatorAuthority: 'coordinator-a',
    });
    t.after(() => reopenedStore.close());
    const reopened = createRemoteSiteCoordinator({
      authorization,
      control,
      journal: control.createCoordinatorJournal('coordinator-a'),
      store: reopenedStore,
      send: async () => {},
      query: async () => {},
      cancel: async () => {},
    });
    assert.equal(reopened.recovered.length, 1);
    assert.deepEqual(reopenedStore.inspectState(dispatch, control), [
      3, 2, 0, 0, 0, 0, false, false, '', '', '',
    ]);
    assert.equal(
      reopened.completionEvidenceAvailable({dispatch}),
      false,
    );
  });

test('Coordinator never queries an intent absent from its durable journal',
  async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-coordinator-missing-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const store = openSqliteCoordinatorDispatchJournal(root, {
      coordinatorAuthority: 'coordinator-a',
    });
    t.after(() => store.close());
    let called = false;
    const coordinator = createRemoteSiteCoordinator({
      authorization,
      control,
      journal: control.createCoordinatorJournal('coordinator-a'),
      store,
      send: async () => {},
      query: async () => { called = true; },
      cancel: async () => { called = true; },
    });
    await assert.rejects(
      async () => coordinator.query({dispatch: request('dispatch-a')}),
      {code: 'RemoteDispatchIntentMissing'},
    );
    assert.equal(called, false);
  });

test('Site status cannot replace evidence or rewrite one Site revision',
  async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-coordinator-status-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const store = openSqliteCoordinatorDispatchJournal(root, {
      coordinatorAuthority: 'coordinator-a',
    });
    t.after(() => store.close());
    const dispatch = request('dispatch-status');
    const coordinator = createRemoteSiteCoordinator({
      authorization,
      control,
      journal: control.createCoordinatorJournal('coordinator-a'),
      store,
      send: async () => Object.freeze({
        revision: 7,
        state: [3, 2, 0, 1, 0],
      }),
      query: async () => Object.freeze({
        revision: 7,
        state: [5, 0, 2, 0, 0],
      }),
      cancel: async () => {},
    });
    await coordinator.dispatch({dispatch});
    assert.equal(
      coordinator.completionEvidenceAvailable({dispatch}),
      false,
    );
    assert.deepEqual(store.inspectState(dispatch, control), [
      1, 2, 7, 3, 2, 0, true, false, '', '', '',
    ]);
    await assert.rejects(
      coordinator.query({dispatch}),
      {code: 'MoonBitHostFailure'},
    );
    assert.deepEqual(store.inspectState(dispatch, control), [
      2, 1, 7, 3, 2, 0, true, false, '', '', '',
    ]);
  });

test('Coordinator retries one durable unknown output after restart', async t => {
  await mkdir(scratch, {recursive: true});
  const root = await mkdtemp(join(scratch, 'coordinator-output-unknown-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const dispatch = request('dispatch-output-unknown');
  const fixture = outputFixture(dispatch);
  const firstStore = openSqliteCoordinatorDispatchJournal(root, {
    coordinatorAuthority: 'coordinator-a',
  });
  const first = createRemoteSiteCoordinator({
    authorization,
    control,
    transferControl,
    journal: control.createCoordinatorJournal('coordinator-a'),
    store: firstStore,
    send: async () => Object.freeze({
      revision: 0,
      state: [0, 0, 0, 0, 0],
    }),
    output: async () => {
      throw Object.assign(new Error('OutputResponseLost'), {
        code: 'OutputResponseLost',
      });
    },
  });
  await first.dispatch({dispatch});
  await assert.rejects(
    first.output({dispatch, ...fixture}),
    {code: 'OutputResponseLost'},
  );
  firstStore.close();

  const reopenedStore = openSqliteCoordinatorDispatchJournal(root, {
    coordinatorAuthority: 'coordinator-a',
  });
  t.after(() => reopenedStore.close());
  let retries = 0;
  const reopened = createRemoteSiteCoordinator({
    authorization,
    control,
    transferControl,
    journal: control.createCoordinatorJournal('coordinator-a'),
    store: reopenedStore,
    output: async () => {
      retries++;
      return Object.freeze({result: fixture.result});
    },
  });
  assert.equal(reopened.recoveredOutputs.length, 1);
  assert.deepEqual(
    control.coordinatorOutputRecordStatus(
      reopened.recoveredOutputs[0].record,
    ),
    ['1', '1', ''],
  );
  const completed = await reopened.output({dispatch, ...fixture});
  assert.equal(completed.resultCid, control.outputResultIdentity(fixture.result));
  assert.equal(retries, 1);
  const replayed = await reopened.output({dispatch, ...fixture});
  assert.deepEqual(replayed, completed);
  assert.equal(retries, 1);
});

test('output planning failure creates no durable output operation', async t => {
  await mkdir(scratch, {recursive: true});
  const root = await mkdtemp(join(scratch, 'coordinator-output-plan-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const dispatch = request('dispatch-output-plan-failure');
  const fixture = outputFixture(dispatch);
  const store = openSqliteCoordinatorDispatchJournal(root, {
    coordinatorAuthority: 'coordinator-a',
  });
  t.after(() => store.close());
  let physicalOutputStarted = false;
  const coordinator = createRemoteSiteCoordinator({
    authorization,
    control,
    transferControl,
    journal: control.createCoordinatorJournal('coordinator-a'),
    store,
    send: async () => Object.freeze({
      revision: 0,
      state: [0, 0, 0, 0, 0],
    }),
    plan: async () => {
      throw Object.assign(new Error('OutputPlanRejected'), {
        code: 'OutputPlanRejected',
      });
    },
    output: async () => {
      physicalOutputStarted = true;
    },
  });
  await coordinator.dispatch({dispatch});
  await assert.rejects(
    coordinator.output({
      dispatch,
      intent: fixture.intent,
      subject: Object.freeze({}),
      maxChunks: 4,
      maxManifestBytes: 4096,
      maxReferencedBytes: 12n,
    }),
    {code: 'OutputPlanRejected'},
  );
  assert.equal(physicalOutputStarted, false);
  assert.equal(store.hasOutputOperations(), false);
});

test('Store output waits for exact destination commit', async t => {
  await mkdir(scratch, {recursive: true});
  const root = await mkdtemp(join(scratch, 'coordinator-store-output-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const dispatch = request('dispatch-store-output');
  const fixture = outputFixture(dispatch, 'store');
  const store = openSqliteCoordinatorDispatchJournal(root, {
    coordinatorAuthority: 'coordinator-a',
  });
  t.after(() => store.close());
  const calls = [];
  const coordinator = createRemoteSiteCoordinator({
    authorization,
    control,
    transferControl,
    journal: control.createCoordinatorJournal('coordinator-a'),
    store,
    send: async () => Object.freeze({
      revision: 0,
      state: [0, 0, 0, 0, 0],
    }),
    output: async ({transferRequest}) => {
      calls.push('source');
      assert.equal(
        transferControl.identity(transferRequest),
        transferControl.identity(fixture.transferRequest),
      );
      return Object.freeze({result: fixture.result});
    },
    receiveStoreOutput: async ({transferRequest}) => {
      calls.push('destination');
      assert.equal(
        transferControl.identity(transferRequest),
        transferControl.identity(fixture.transferRequest),
      );
      return Object.freeze({
        record: fixture.transferRecord,
      });
    },
  });
  await coordinator.dispatch({dispatch});
  const completed = await coordinator.output({dispatch, ...fixture});
  assert.equal(completed.transferRequestCid,
    transferControl.identity(fixture.transferRequest));
  assert.deepEqual(calls.sort(), ['destination', 'source']);
});

test('Store output requires the exact committed destination record',
  async t => {
    const cases = [
      ['undefined', () => undefined, 'InvalidRemoteCoordinatorStoreOutputResult'],
      ['null', () => null, 'InvalidRemoteCoordinatorStoreOutputResult'],
      ['missing record', () => Object.freeze({}),
        'InvalidRemoteCoordinatorStoreOutputResult'],
      ['uncommitted', fixture => Object.freeze({
        record: transferControl.open(fixture.transferRequest),
      }), 'InvalidRemoteCoordinatorStoreOutputResult'],
      ['foreign request', (_fixture, foreign) => Object.freeze({
        record: foreign.transferRecord,
      }), 'RemoteCoordinatorStoreOutputCollision'],
    ];
    for (const [name, destination, code] of cases) {
      await t.test(name, async subtest => {
        await mkdir(scratch, {recursive: true});
        const root = await mkdtemp(join(scratch, 'coordinator-store-exact-'));
        subtest.after(() => rm(root, {recursive: true, force: true}));
        const dispatch = request(`dispatch-store-${name.replaceAll(' ', '-')}`);
        const fixture = outputFixture(dispatch, 'store');
        const foreign = outputFixture(dispatch, 'store', {
          transferAttemptId: 'transfer-foreign-output',
          destinationSite: 'site-c',
          destinationSiteGeneration: 3,
          materialGeneration: cid('0'),
        });
        const store = openSqliteCoordinatorDispatchJournal(root, {
          coordinatorAuthority: 'coordinator-a',
        });
        subtest.after(() => store.close());
        const journal = control.createCoordinatorJournal('coordinator-a');
        const coordinator = createRemoteSiteCoordinator({
          authorization,
          control,
          transferControl,
          journal,
          store,
          send: async () => Object.freeze({
            revision: 0,
            state: [0, 0, 0, 0, 0],
          }),
          output: async () => Object.freeze({result: fixture.result}),
          receiveStoreOutput: async () => destination(fixture, foreign),
        });
        await coordinator.dispatch({dispatch});
        await assert.rejects(
          coordinator.output({dispatch, ...fixture}),
          {code},
        );
        const recoveryJournal = control.createCoordinatorJournal(
          'coordinator-a',
        );
        store.recoverJournal(recoveryJournal, control);
        const recovered = store.recoverOutputs(
          recoveryJournal,
          control,
          transferControl,
        );
        assert.equal(recovered.length, 1);
        assert.notEqual(
          store.inspectOutput(recovered[0].record, control).progress,
          2,
        );
      });
    }
  });

test('output owner retains a continuing sibling and prevents duplicate I/O',
  async t => {
    await mkdir(scratch, {recursive: true});
    const root = await mkdtemp(join(scratch, 'coordinator-output-owner-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const dispatch = request('dispatch-output-owner');
    const fixture = outputFixture(dispatch, 'store');
    const store = openSqliteCoordinatorDispatchJournal(root, {
      coordinatorAuthority: 'coordinator-a',
    });
    t.after(() => store.close());
    let sourceCalls = 0;
    let destinationCalls = 0;
    let settleDestination;
    const destinationPending = new Promise(resolve => {
      settleDestination = resolve;
    });
    const coordinator = createRemoteSiteCoordinator({
      authorization,
      control,
      transferControl,
      journal: control.createCoordinatorJournal('coordinator-a'),
      store,
      send: async () => Object.freeze({
        revision: 0,
        state: [0, 0, 0, 0, 0],
      }),
      output: async () => {
        sourceCalls++;
        if (sourceCalls === 1) {
          throw Object.assign(new Error('SourceOutputFailed'), {
            code: 'SourceOutputFailed',
          });
        }
        return Object.freeze({result: fixture.result});
      },
      receiveStoreOutput: async () => {
        destinationCalls++;
        if (destinationCalls === 1) return await destinationPending;
        return Object.freeze({record: fixture.transferRecord});
      },
    });
    await coordinator.dispatch({dispatch});
    const failure = await coordinator.output({dispatch, ...fixture}).then(
      () => assert.fail('output should fail'),
      error => error,
    );
    assert.equal(failure.code, 'SourceOutputFailed');
    assert.equal(failure.cleanupPending, true);
    assert.equal(failure.cleanupHandle.status().pending, true);
    const joined = await coordinator.output({dispatch, ...fixture}).then(
      () => assert.fail('joined output should fail'),
      error => error,
    );
    assert.equal(joined, failure);
    assert.equal(sourceCalls, 1);
    assert.equal(destinationCalls, 1);
    settleDestination(Object.freeze({record: fixture.transferRecord}));
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(failure.cleanupHandle.status().pending, false);
    const completed = await coordinator.output({dispatch, ...fixture});
    assert.equal(completed.resultCid, control.outputResultIdentity(fixture.result));
    assert.equal(sourceCalls, 2);
    assert.equal(destinationCalls, 2);
  });

test('destination failure retains a synchronously started source', async t => {
  await mkdir(scratch, {recursive: true});
  const root = await mkdtemp(join(scratch, 'coordinator-source-owner-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const dispatch = request('dispatch-source-owner');
  const fixture = outputFixture(dispatch, 'store');
  const store = openSqliteCoordinatorDispatchJournal(root, {
    coordinatorAuthority: 'coordinator-a',
  });
  t.after(() => store.close());
  let sourceCalls = 0;
  let destinationCalls = 0;
  let sourceSignal;
  let settleSource;
  const sourcePending = new Promise(resolve => { settleSource = resolve; });
  const coordinator = createRemoteSiteCoordinator({
    authorization,
    control,
    transferControl,
    journal: control.createCoordinatorJournal('coordinator-a'),
    store,
    send: async () => Object.freeze({
      revision: 0,
      state: [0, 0, 0, 0, 0],
    }),
    output: ({signal}) => {
      sourceCalls++;
      sourceSignal = signal;
      return sourcePending;
    },
    receiveStoreOutput: () => {
      destinationCalls++;
      throw Object.assign(new Error('DestinationOutputFailed'), {
        code: 'DestinationOutputFailed',
      });
    },
  });
  await coordinator.dispatch({dispatch});
  const failure = await coordinator.output({dispatch, ...fixture}).then(
    () => assert.fail('output should fail'),
    error => error,
  );
  assert.equal(failure.code, 'DestinationOutputFailed');
  assert.equal(failure.cleanupPending, true);
  assert.equal(sourceSignal.aborted, true);
  await coordinator.output({dispatch, ...fixture}).catch(() => {});
  assert.equal(sourceCalls, 1);
  assert.equal(destinationCalls, 1);
  settleSource(Object.freeze({result: fixture.result}));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(failure.cleanupHandle.status().pending, false);
});

test('output cleanup owner retries child cleanup without new physical I/O',
  async t => {
    await mkdir(scratch, {recursive: true});
    const root = await mkdtemp(join(scratch, 'coordinator-output-cleanup-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const dispatch = request('dispatch-output-cleanup');
    const fixture = outputFixture(dispatch, 'store');
    const store = openSqliteCoordinatorDispatchJournal(root, {
      coordinatorAuthority: 'coordinator-a',
    });
    t.after(() => store.close());
    let sourceCalls = 0;
    let retries = 0;
    let cleanupPending = true;
    const childCleanup = Object.freeze({
      status: () => Object.freeze({pending: cleanupPending}),
      async retry() {
        retries++;
        if (retries <= 2) throw new Error('StopStillPending');
        cleanupPending = false;
        return this.status();
      },
    });
    const coordinator = createRemoteSiteCoordinator({
      authorization,
      control,
      transferControl,
      journal: control.createCoordinatorJournal('coordinator-a'),
      store,
      send: async () => Object.freeze({
        revision: 0,
        state: [0, 0, 0, 0, 0],
      }),
      output: async () => {
        sourceCalls++;
        throw Object.assign(new Error('SourceStopUnconfirmed'), {
          code: 'SourceStopUnconfirmed',
          cleanupPending: true,
          cleanupHandle: childCleanup,
        });
      },
      receiveStoreOutput: async () => Object.freeze({
        record: fixture.transferRecord,
      }),
    });
    await coordinator.dispatch({dispatch});
    const failure = await coordinator.output({dispatch, ...fixture}).then(
      () => assert.fail('output should fail'),
      error => error,
    );
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.equal((await failure.cleanupHandle.retry()).pending, true);
    assert.equal((await failure.cleanupHandle.retry()).pending, true);
    assert.equal(sourceCalls, 1);
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(retries, 3);
  });

// Remote dispatch boundary: the Run owner's gate decides before the durable
// intent and before any send. The Site keeps its own mTLS/authority checks.
async function dispatchUnderAuthorization(t, gate, dispatchId, signal) {
  await mkdir(scratch, {recursive: true});
  const root = await mkdtemp(join(scratch, 'coordinator-authorization-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const store = openSqliteCoordinatorDispatchJournal(root, {
    coordinatorAuthority: 'coordinator-a',
  });
  t.after(() => store.close());
  let sends = 0;
  const coordinator = createRemoteSiteCoordinator({
    authorization: gate,
    control,
    journal: control.createCoordinatorJournal('coordinator-a'),
    store,
    send: async () => {
      sends++;
      return Object.freeze({revision: 0, state: [0, 0, 0, 0, 0]});
    },
  });
  const dispatch = request(dispatchId);
  let error;
  try { await coordinator.dispatch({dispatch, signal}); }
  catch (reason) { error = reason; }
  return {sends, error, recorded: store.contains(dispatch, control)};
}

const remoteEntries = outcome => [accountEntry('remote-site-a', outcome, {
  connection: 'site-a', operation: 'write',
})];
const remotePermit = view => ({decision: 'permit', subject: view.subject,
  authority: 'reviewer'});

test('remote dispatch: allow and permit send; refusals record and send nothing',
  async t => {
    let hostCalls = 0;
    const counting = decide => decide === undefined ? undefined
      : view => { hostCalls++; return decide(view); };
    const allow = await fixtureAuthorization(remoteEntries('allow'), {
      decide: counting(remotePermit), answeringAuthorities: ['reviewer'],
    });
    const allowed = await dispatchUnderAuthorization(t, allow, 'auth-allow');
    assert.equal(allowed.error, undefined);
    assert.equal(allowed.sends, 1);
    assert.equal(allowed.recorded, true);
    assert.equal(hostCalls, 0);
    assert.equal(allow.counters().checkpointsPersisted, 0);
    const [decision] = [await allow.authorize('activation', {
      connection: 'site-a', resource: 'local', operation: 'write',
    }, {subjectCid: cid('0')})];
    assert.equal(decision.action, 'dispatch');

    const cases = [
      ['permit', remoteEntries('delegate'), remotePermit, undefined, 1],
      ['explicit deny', remoteEntries('deny'), undefined,
        'ExecutionAuthorizationDenied', 0],
      ['no-match deny', [accountEntry('other-site', 'allow', {
        connection: 'site-b',
      })], undefined, 'ExecutionAuthorizationDenied', 0],
      ['reject', remoteEntries('delegate'), view => ({decision: 'reject',
        subject: view.subject, authority: 'reviewer'}),
      'ExecutionAuthorizationDenied', 0],
      ['throw', remoteEntries('delegate'), () => {
        throw new Error('DecisionServiceDown');
      }, 'ExecutionAuthorizationDecisionFailed', 0],
      ['timeout', remoteEntries('delegate'), () => new Promise(() => {}),
        'ExecutionAuthorizationDecisionFailed', 0],
      ['malformed', remoteEntries('delegate'), () => 'permit',
        'ExecutionAuthorizationDecisionFailed', 0],
      ['defer without journal', remoteEntries('delegate'), view => ({
        decision: 'defer', subject: view.subject,
      }), 'ExecutionAuthorizationDeferralUnsupported', 0],
    ];
    for (const [label, entries, decide, code, sends] of cases) {
      const before = hostCalls;
      const gate = await fixtureAuthorization(entries, {
        decide: counting(decide), answeringAuthorities: ['reviewer'],
        decisionTimeoutMs: 20,
      });
      const result = await dispatchUnderAuthorization(t, gate,
        `auth-${label.replaceAll(' ', '-')}`);
      assert.equal(result.error?.code, code, label);
      assert.equal(result.sends, sends, label);
      assert.equal(result.recorded, sends === 1, label);
      assert.equal(hostCalls - before, decide === undefined ? 0 : 1, label);
    }
  });

test('deferred remote dispatch persists its Checkpoint before waiting',
  async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-remote-deferral-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const deferral = await sqliteDeferral(root);
    t.after(() => deferral.journal.close());
    const gate = await fixtureAuthorization(remoteEntries('delegate'), {
      decide: view => ({decision: 'defer', subject: view.subject}),
      answeringAuthorities: ['reviewer'],
      deferral,
    });
    const waiting = await dispatchUnderAuthorization(t, gate, 'auth-defer');
    assert.equal(waiting.error?.code, 'ExecutionAuthorizationWaiting');
    assert.equal(waiting.sends, 0);
    assert.equal(waiting.recorded, false);
    const checkpoint = waiting.error.authorization.checkpoint;
    assert.equal(deferral.journal.getRunState(checkpoint.runId).status,
      'waiting_checkpoint');
    assert.equal(gate.counters().checkpointsPersisted, 1);
    // The Checkpoint requires the dispatch's sealed subject artifact itself;
    // the Site/registration decision subject is bound next to it.
    const persisted = deferral.journal.inspect(checkpoint.checkpointCid);
    assert.match(waiting.error.authorization.subjectCid,
      /^sha256:[0-9a-f]{64}$/);
    assert.equal(persisted.requiredArtifact.cid,
      waiting.error.authorization.subjectCid);
    assert.equal(persisted.decisionSubjectCid, checkpoint.decisionSubjectCid);
    assert.notEqual(persisted.decisionSubjectCid, persisted.requiredArtifact.cid);
  });

test('a remote retry under a changed context is decided again', async t => {
  const answers = ['permit', 'reject'];
  let calls = 0;
  const gate = await fixtureAuthorization(remoteEntries('delegate'), {
    decide: view => ({decision: answers[calls++], subject: view.subject,
      authority: 'reviewer'}),
    answeringAuthorities: ['reviewer'],
  });
  const first = await dispatchUnderAuthorization(t, gate, 'auth-retry-a');
  assert.equal(first.sends, 1);
  // Same Run, Site and registration: the exact permit is reused.
  const second = await dispatchUnderAuthorization(t, gate, 'auth-retry-b');
  assert.equal(second.sends, 1);
  assert.equal(calls, 1);
  const changed = gate.withContext({
    principal: FIXTURE_CONTEXT.principal,
    contextCid: cid('9'),
  });
  const retried = await dispatchUnderAuthorization(t, changed, 'auth-retry-c');
  assert.equal(calls, 2);
  assert.equal(retried.error?.code, 'ExecutionAuthorizationDenied');
  assert.equal(retried.sends, 0);
  assert.equal(retried.recorded, false);
});

test('remote output egress is authorized before durable output and I/O',
  async t => {
    await mkdir(scratch, {recursive: true});
    const root = await mkdtemp(join(scratch, 'coordinator-output-authorization-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const dispatch = request('dispatch-output-authorization');
    const fixture = outputFixture(dispatch);
    const store = openSqliteCoordinatorDispatchJournal(root, {
      coordinatorAuthority: 'coordinator-a',
    });
    t.after(() => store.close());
    // Dispatch to site-a is allowed; egress to site-b is not configured.
    const gate = await fixtureAuthorization(remoteEntries('allow'));
    let outputs = 0;
    const coordinator = createRemoteSiteCoordinator({
      authorization: gate,
      control,
      transferControl,
      journal: control.createCoordinatorJournal('coordinator-a'),
      store,
      send: async () => Object.freeze({revision: 0, state: [0, 0, 0, 0, 0]}),
      output: async () => {
        outputs++;
        return Object.freeze({result: fixture.result});
      },
    });
    await coordinator.dispatch({dispatch});
    await assert.rejects(
      coordinator.output({dispatch, ...fixture}),
      error => error.code === 'ExecutionAuthorizationDenied' &&
        error.authorization.boundary === 'transfer' &&
        error.authorization.tuple.connection === 'site-b',
    );
    assert.equal(outputs, 0);

    // Canonical account configuration orders entries by entry_id.
    const egress = await fixtureAuthorization([
      accountEntry('egress-site-b', 'allow', {
        connection: 'site-b', operation: 'write',
      }),
      ...remoteEntries('allow'),
    ]);
    const permitted = createRemoteSiteCoordinator({
      authorization: egress,
      control,
      transferControl,
      journal: control.createCoordinatorJournal('coordinator-a'),
      store,
      output: async () => {
        outputs++;
        return Object.freeze({result: fixture.result});
      },
    });
    // The refused egress left no durable output operation to recover.
    assert.equal(permitted.recoveredOutputs.length, 0);
    const completed = await permitted.output({dispatch, ...fixture});
    assert.equal(completed.resultCid,
      control.outputResultIdentity(fixture.result));
    assert.equal(outputs, 1);
    assert.equal(egress.counters().hostDecisionCalls, 0);
  });
