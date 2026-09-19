import assert from 'node:assert/strict';
import {execFileSync, fork} from 'node:child_process';
import {once} from 'node:events';
import {readFile, mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {X509Certificate} from 'node:crypto';
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

const cid = digit => `sha256:${digit.repeat(64)}`;
const runtime = runtimeCore(moon);
const dispatchBudget = runtime.remoteSiteControl.prepareBudget({
  retainedBytes: 64n,
  executionBytes: 16n,
});
const dispatchBudgetCid = runtime.remoteSiteControl.budgetIdentity(
  dispatchBudget,
);

function openssl(root, ...arguments_) {
  execFileSync('openssl', arguments_, {cwd: root, stdio: 'ignore'});
}

function issueCertificate(root, name, subject, extensionFile) {
  openssl(root, 'genrsa', '-out', `${name}.key`, '2048');
  openssl(
    root,
    'req',
    '-new',
    '-key', `${name}.key`,
    '-out', `${name}.csr`,
    '-subj', subject,
  );
  openssl(
    root,
    'x509',
    '-req',
    '-in', `${name}.csr`,
    '-CA', 'ca.crt',
    '-CAkey', 'ca.key',
    '-CAcreateserial',
    '-out', `${name}.crt`,
    '-days', '1',
    ...(extensionFile === undefined ? [] : ['-extfile', extensionFile]),
  );
}

async function certificates(root) {
  openssl(root, 'genrsa', '-out', 'ca.key', '2048');
  openssl(
    root,
    'req',
    '-x509',
    '-new',
    '-key', 'ca.key',
    '-out', 'ca.crt',
    '-subj', '/CN=ActQL Remote Test CA',
    '-days', '1',
  );
  await writeFile(
    join(root, 'site.ext'),
    'subjectAltName=DNS:localhost,IP:127.0.0.1\n',
  );
  issueCertificate(root, 'site', '/CN=localhost', 'site.ext');
  issueCertificate(root, 'coordinator', '/CN=coordinator-a');
  issueCertificate(root, 'foreign', '/CN=foreign-coordinator');
  const read = name => readFile(join(root, name));
  const coordinatorCertificate = await read('coordinator.crt');
  return Object.freeze({
    ca: await read('ca.crt'),
    siteKey: await read('site.key'),
    siteCertificate: await read('site.crt'),
    coordinatorKey: await read('coordinator.key'),
    coordinatorCertificate,
    coordinatorFingerprint: new X509Certificate(
      coordinatorCertificate,
    ).fingerprint256,
    foreignKey: await read('foreign.key'),
    foreignCertificate: await read('foreign.crt'),
  });
}

const dispatch = (dispatchId = 'dispatch-a', revision = 'local/1') =>
  runtime.remoteSiteControl.prepare(Object.freeze({
    coordinatorAuthority: 'coordinator-a',
    runDefinitionCid: cid('0'),
    taskKey: 'task-a',
    taskAttempt: 1,
    dispatchId,
    siteKey: 'site-a',
    siteGeneration: 1,
    runtimeBundleCid: cid('a'),
    connectorRegistration: 'local',
    connectorRevision: revision,
    strategyRevision: 'strategy/1',
    inputBindingCid: cid('1'),
    obligationsCid: cid('2'),
    budgetCid: dispatchBudgetCid,
    evidenceIssuerCapabilityCid: cid('b'),
    grantCid: cid('4'),
  }));

async function startFixture(root, material, {delayMs = 0} = {}) {
  const configurationPath = join(root, 'agent.json');
  await writeFile(configurationPath, JSON.stringify({
    keyPath: join(root, 'site.key'),
    certPath: join(root, 'site.crt'),
    caPath: join(root, 'ca.crt'),
    storeRoot: join(root, 'site-store'),
    coordinatorAuthorities: [
      [material.coordinatorFingerprint, 'coordinator-a'],
    ],
    site: {
      key: 'site-a',
      generation: 1,
      runtimeRevision: cid('a'),
      maxConcurrentOperations: 4,
      maxConcurrentTransfers: 4,
      maxRetainedBytes: '1048576',
      maxExecutionBytes: '1048576',
    },
    runtime: {
      runtimeBundleCid: cid('a'),
      connectorRegistration: 'local',
      connectorRevision: 'local/1',
      strategyRevision: 'strategy/1',
      operationCapabilityCid: cid('4'),
      evidenceKind: runtime.remoteSiteControl.managedOutputEvidenceKind,
      issuerCapabilityCid: cid('b'),
      delayMs,
      output: {
        materialGeneration: 'material-generation-a',
        holdingEvidenceCid: cid('c'),
        managedProfileCid: cid('3'),
        measurement: {
          rowCount: 2,
          admissionNodes: 0,
          admissionTextBytes: 0,
          admissionWork: 0,
          columnRows: [2],
          columnBytes: [2],
          columnNodes: [2],
          columnMaxValueBytes: [1],
          columnNullRows: [0],
          columnAdmittedDepths: [10],
        },
        resultSchemaCid: cid('5'),
        logicalViewCid: cid('6'),
        representationCodecCid: cid('7'),
        physicalManifestCid: cid('8'),
        rowCount: 2,
        retainedBytes: '8',
      },
    },
    budgets: [{retainedBytes: '64', executionBytes: '16'}],
  }), {mode: 0o600});
  const child = fork(
    new URL('./https-agent-fixture.mjs', import.meta.url),
    [configurationPath],
    {stdio: ['ignore', 'ignore', 'pipe', 'ipc']},
  );
  let errors = '';
  child.stderr.setEncoding('utf8');
  child.stderr.on('data', value => { errors += value; });
  const ready = await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      reject(new Error(`Remote Site fixture timeout: ${errors}`));
    }, 10_000);
    child.once('error', error => {
      clearTimeout(timeout);
      reject(error);
    });
    child.on('message', message => {
      if (message?.type === 'ready') {
        clearTimeout(timeout);
        resolve(message);
      }
    });
    child.once('exit', code => {
      clearTimeout(timeout);
      reject(new Error(`Remote Site fixture exited ${code}: ${errors}`));
    });
  });
  return Object.freeze({
    origin: `https://127.0.0.1:${ready.port}`,
    child,
    async close() {
      if (child.exitCode !== null) return;
      child.send({type: 'close'});
      await once(child, 'exit');
    },
  });
}

async function terminalStatus(options, query = queryRemoteDispatch) {
  for (let attempt = 0; attempt < 100; attempt++) {
    const status = await query(options);
    if (status.state[0] >= 3) return status;
    await new Promise(resolve => setTimeout(resolve, 5));
  }
  throw new Error('Remote dispatch did not reach terminal state');
}

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
      control: runtime.remoteSiteControl,
      journal: runtime.remoteSiteControl.createCoordinatorJournal(
        'coordinator-a',
      ),
      store: coordinatorStore,
    });
    const request = dispatch();
    const options = {
      origin: fixture.origin,
      ca: material.ca,
      cert: material.coordinatorCertificate,
      key: material.coordinatorKey,
      control: runtime.remoteSiteControl,
      dispatch: request,
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

    await assert.rejects(
      sendRemoteDispatch({...options, dispatch: dispatch('dispatch-a', 'local/2')}),
      error => error.code === 'RemoteSiteRejected' && error.status === 400,
    );
    await assert.rejects(
      sendRemoteDispatch({
        ...options,
        cert: material.foreignCertificate,
        key: material.foreignKey,
      }),
      error => error.code === 'RemoteSiteRejected' && error.status === 404,
    );
    coordinatorStore.close();
    const reopenedStore = openSqliteCoordinatorDispatchJournal(
      join(root, 'coordinator'),
      {coordinatorAuthority: 'coordinator-a'},
    );
    t.after(() => reopenedStore.close());
    const reopened = createRemoteSiteCoordinator({
      control: runtime.remoteSiteControl,
      journal: runtime.remoteSiteControl.createCoordinatorJournal(
        'coordinator-a',
      ),
      store: reopenedStore,
    });
    assert.equal(reopened.recovered.length, 1);
    assert.equal(reopened.completionEvidenceAvailable(options), true);
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

test('authenticated cancellation waits for physical handler exit', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-remote-cancel-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const material = await certificates(root);
  const fixture = await startFixture(root, material, {delayMs: 10_000});
  t.after(() => fixture.close());
  const request = dispatch('dispatch-cancel');
  const options = {
    origin: fixture.origin,
    ca: material.ca,
    cert: material.coordinatorCertificate,
    key: material.coordinatorKey,
    control: runtime.remoteSiteControl,
    dispatch: request,
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
      control: {runtimeStartable: () => false},
      admitDispatchJson() {},
      dispatchRuntime: {
        supports: () => false,
        start() {},
        cancel() {},
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
      control: {runtimeStartable: () => false},
      admitDispatchJson() {},
      dispatchRuntime: {
        supports: () => false,
        start() {},
        cancel() {},
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
