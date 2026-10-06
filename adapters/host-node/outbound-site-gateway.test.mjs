import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash, X509Certificate} from 'node:crypto';
import {request as httpsRequest} from 'node:https';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openSqliteDispatchJournal} from
  '../site-node/sqlite-dispatch-journal.mjs';
import {openSqliteCoordinatorDispatchJournal} from
  './sqlite-coordinator-journal.mjs';
import {startHttpsOutboundSiteGateway} from './outbound-site-gateway.mjs';
import {createRemoteSiteCoordinator} from './remote-site-coordinator.mjs';
import {allowAllAuthorization} from './authorization-fixture.mjs';

// Run-owner account for these transport tests: dispatch and egress are
// explicitly allowed; authorization outcomes are covered elsewhere.
const remoteAuthorization = await allowAllAuthorization();

const cid = digit => `sha256:${digit.repeat(64)}`;
const physicalCid = value =>
  `sha256:${createHash('sha256').update(value).digest('hex')}`;
const runtime = runtimeCore(moon);
const control = runtime.remoteSiteControl;
const transferControl = runtime.remoteTransferControl;
const scratch = fileURLToPath(new URL('../../../actql-test-runs/', import.meta.url));

function openssl(root, ...arguments_) {
  execFileSync('openssl', arguments_, {
    cwd: root, stdio: ['ignore', 'pipe', 'pipe'],
  });
}

function issue(root, name, subject, extension) {
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
    ...(extension === undefined ? [] : ['-extfile', extension]),
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
    '-subj', '/CN=ActQL Outbound Test CA',
    '-days', '1',
  );
  await writeFile(
    join(root, 'server.ext'),
    'subjectAltName=DNS:localhost,IP:127.0.0.1\n' +
      'extendedKeyUsage=serverAuth\n',
  );
  await writeFile(
    join(root, 'client.ext'),
    'extendedKeyUsage=clientAuth\n',
  );
  issue(root, 'server', '/CN=localhost', 'server.ext');
  issue(root, 'site', '/CN=site-a', 'client.ext');
  issue(root, 'foreign', '/CN=foreign-site', 'client.ext');
  const read = name => readFile(join(root, name));
  const siteCertificate = await read('site.crt');
  return Object.freeze({
    ca: await read('ca.crt'),
    serverKey: await read('server.key'),
    serverCertificate: await read('server.crt'),
    siteKey: await read('site.key'),
    siteCertificate,
    siteFingerprint: new X509Certificate(siteCertificate).fingerprint256,
    foreignKey: await read('foreign.key'),
    foreignCertificate: await read('foreign.crt'),
  });
}

function post(origin, path, material, body = '{}') {
  const bytes = Buffer.from(body, 'utf8');
  return new Promise((resolve, reject) => {
    const request = httpsRequest(new URL(path, origin), {
      method: 'POST',
      ca: material.ca,
      cert: material.cert,
      key: material.key,
      servername: 'localhost',
      minVersion: 'TLSv1.3',
      headers: {
        'content-type': 'application/json',
        'content-length': String(bytes.byteLength),
      },
    }, response => {
      const chunks = [];
      response.on('data', chunk => chunks.push(chunk));
      response.on('error', reject);
      response.on('end', () => resolve(Object.freeze({
        status: response.statusCode,
        body: Buffer.concat(chunks).toString('utf8'),
      })));
    });
    request.on('error', reject);
    request.end(bytes);
  });
}

function postWithLostAck(origin, path, material, body) {
  return new Promise((resolve, reject) => {
    const request = httpsRequest(new URL(path, origin), {
      method: 'POST', ca: material.ca, cert: material.cert, key: material.key,
      servername: 'localhost', minVersion: 'TLSv1.3',
      headers: {'content-type': 'application/json',
        'content-length': Buffer.byteLength(body)},
    }, response => {
      assert.equal(response.statusCode, 200);
      // Lose the ACK body on the actual client stream after the server's
      // admission commit, rather than merely pretending an inspected ACK failed.
      response.on('error', reject);
      response.destroy(Object.assign(new Error('ACK_LOST'), {code: 'ACK_LOST'}));
    });
    request.on('error', reject);
    request.end(body);
  });
}

test('retained-input transport requires every admission and custody hook', async () => {
  const names = ['retainedInputIntentFacts', 'retainedInputPlanEnvelope',
    'admitRetainedInputPlan', 'retainedInputPlanFacts',
    'retainedInputTransferEnvelope', 'admitRetainedInputResult'];
  const owner = Object.fromEntries(names.map(name => [name, () => {}]));
  const options = {key: Buffer.from('unused'), cert: Buffer.from('unused'),
    ca: Buffer.from('unused'), bearerAuthorities: new Map([
      [physicalCid('test-token').slice(7), {siteKey: 'site-a', siteGeneration: 1}]]),
    control, retainedInput: owner, receiveRetainedInput: async () => {}};
  for (const name of names) {
    const incomplete = {...owner};
    delete incomplete[name];
    await assert.rejects(startHttpsOutboundSiteGateway({...options, retainedInput: incomplete}),
      {code: 'InvalidOutboundSiteGatewayConfiguration'});
  }
  await assert.rejects(startHttpsOutboundSiteGateway({...options, receiveRetainedInput: undefined}),
    {code: 'InvalidOutboundSiteGatewayConfiguration'});
});

test('retained-input transport keeps its obligation across stale status and custody failure',
  {timeout: 30_000}, async t => {
    await mkdir(scratch, {recursive: true});
    const root = await mkdtemp(join(scratch, 'outbound-retained-custody-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const material = await certificates(root);
    const request = dispatch({dispatchId: 'retained-custody'});
    const identity = control.identity(request);
    // Transport fault isolation: this injected admission port is deliberately
    // not protocol/Native execution evidence. The actual owner and Native
    // process are exercised by test-native-resident-site's retained case.
    const intent = Object.freeze({wire: 'intent'});
    const envelope = '{"test":"retained-plan-envelope"}';
    const report = '{"test":"retained-plan-report"}';
    const admitted = Object.freeze({plan: 'admitted'});
    const retainedInput = {
      retainedInputIntentFacts: () => ({wire: JSON.stringify({dispatch_request_cid: identity})}),
      retainedInputPlanEnvelope: () => envelope,
      admitRetainedInputPlan: (_intent, saved) => {
        assert.equal(saved.wire, report);
        assert.equal(saved.cid, physicalCid(report));
        return admitted;
      },
      retainedInputPlanFacts: () => ({wire: JSON.stringify({dispatch_request_cid: identity})}),
      retainedInputTransferEnvelope: () => { throw new Error('unused'); },
      admitRetainedInputResult: () => { throw new Error('unused'); },
    };
    let custodyCalls = 0;
    let ordinaryObservations = 0;
    const gateway = await startHttpsOutboundSiteGateway({
      key: material.serverKey, cert: material.serverCertificate, ca: material.ca,
      siteAuthorities: new Map([[material.siteFingerprint,
        {siteKey: 'site-a', siteGeneration: 1}]]), control, retainedInput,
      receiveRetainedInput: async value => {
        assert.equal(value.admitted, admitted);
        assert.equal(value.operation, 'retained-plan');
        if (++custodyCalls === 1) throw new Error('custody unconfirmed');
      },
      receiveObservation: async value => {
        control.admitResponseJson(value.body, request, false);
        ordinaryObservations++;
        return Object.freeze({});
      },
    });
    t.after(() => gateway.close());
    const controller = new AbortController();
    t.after(() => controller.abort());
    const planned = gateway.retainedPlan({dispatch: request, intent,
      current: {}, limits: {}, signal: controller.signal});
    planned.catch(() => {});
    const path = '/v1/sites/site-a/generations/1/outbound';
    const tls = {ca: material.ca, cert: material.siteCertificate, key: material.siteKey};
    const site = runtime.siteControl.create({key: 'site-a', generation: 1,
      runtimeRevision: cid('a'), maxConcurrentOperations: 4, maxConcurrentTransfers: 4,
      maxRetainedBytes: 1_048_576n, maxExecutionBytes: 1_048_576n});
    const journal = control.createJournal(site);
    const siteStore = openSqliteDispatchJournal(join(root, 'site'), {
      siteKey: 'site-a', siteGeneration: 1, runtimeRevision: cid('a'),
    });
    t.after(() => siteStore.close());
    const accepted = siteStore.accept(control.prepareAdmission(journal, request), request, control);
    const stale = control.replyJson(accepted);
    assert.equal((await post(gateway.origin, `${path}/observations`, tls, stale)).status, 200);
    assert.equal(custodyCalls, 0);
    assert.equal(gateway.pending(), 1);
    assert.equal((await post(gateway.origin, `${path}/poll`, tls)).body, envelope);
    assert.equal((await post(gateway.origin, `${path}/observations`, tls, stale)).status, 200);
    assert.equal(ordinaryObservations, 2);
    assert.equal(gateway.pending(), 1);
    assert.equal((await post(gateway.origin, `${path}/observations`, tls, report)).status, 503);
    assert.equal(gateway.pending(), 1);
    assert.equal((await post(gateway.origin, `${path}/poll`, tls)).body, envelope);
    assert.equal((await post(gateway.origin, `${path}/observations`, tls, report)).status, 200);
    assert.equal(await planned, admitted);
    assert.equal(custodyCalls, 2);
    assert.equal(gateway.pending(), 0);
  });

test('durable observation replay survives lost ACK and restart without a pending dispatch', {timeout: 15_000}, async t => {
  await mkdir(scratch, {recursive: true});
  const root = await mkdtemp(join(scratch, 'outbound-replay-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const materials = await certificates(root);
  const siteMaterial = {ca: materials.ca, cert: materials.siteCertificate, key: materials.siteKey};
  const foreignMaterial = {ca: materials.ca, cert: materials.foreignCertificate, key: materials.foreignKey};
  const storeRoot = join(root, 'coordinator');
  let store = openSqliteCoordinatorDispatchJournal(storeRoot, {coordinatorAuthority: 'coordinator-a'});
  let gateway;
  let receiverCalls = 0;
  let dispatchCalls = 0;
  const createOwner = () => createRemoteSiteCoordinator({
    authorization: remoteAuthorization, control,
    journal: control.createCoordinatorJournal('coordinator-a'), store,
    send: value => { dispatchCalls++; return gateway.dispatch(value); },
  });
  let owner = createOwner();
  const start = () => startHttpsOutboundSiteGateway({
    key: materials.serverKey, cert: materials.serverCertificate, ca: materials.ca,
    siteAuthorities: new Map([
      [materials.siteFingerprint, {siteKey: 'site-a', siteGeneration: 1}],
      [new X509Certificate(materials.foreignCertificate).fingerprint256,
        {siteKey: 'site-a', siteGeneration: 2}],
    ]), control,
    receiveObservation: value => { receiverCalls++; return owner.receiveObservation(value); },
  });
  gateway = await start();
  t.after(async () => { await gateway.close(); store.close(); });
  const request = dispatch();
  const completion = owner.dispatch({dispatch: request, inputBindingBody: '{}'});
  // Register rejection handling immediately; failures below still close the
  // gateway and must not leave an unhandled waiter rejection behind.
  completion.catch(() => {});
  const path = '/v1/sites/site-a/generations/1/outbound';
  const polled = await post(gateway.origin, `${path}/poll`, siteMaterial);
  assert.equal(polled.status, 200);
  const received = control.pollDispatchRequest(control.admitPollDispatch(polled.body));
  assert.equal(control.identity(received), control.identity(request));
  const site = runtime.siteControl.create({key: 'site-a', generation: 1,
    runtimeRevision: cid('a'), maxConcurrentOperations: 4, maxConcurrentTransfers: 4,
    maxRetainedBytes: 1_048_576n, maxExecutionBytes: 1_048_576n});
  const siteJournal = control.createJournal(site);
  const admission = control.prepareAdmission(siteJournal, received);
  const record = control.commitAdmission(admission, true);
  const accepted = control.replyJson(record);
  await assert.rejects(postWithLostAck(gateway.origin, `${path}/observations`, siteMaterial, accepted), {code: 'ACK_LOST'});
  assert.equal(store.inspectState(request, control)[0], 1);
  assert.equal(gateway.pending(), 1);
  control.commitTransition(control.prepareProvisioning(record,
    control.registerExecutionCapability({site, runtimeBundleCid: cid('a'),
      connectorRegistration: 'local', connectorRevision: 'local/1',
      strategyRevision: 'strategy/1', operationCapabilityCid: cid('4')})), true);
  const unadmitted = control.replyJson(record);
  control.commitTransition(control.prepareExecution(record), true);
  const running = control.replyJson(record);
  const runningStatus = control.statusJson(record, undefined, undefined, undefined);

  // COMMIT did persist the observation, but its return was lost. This request
  // must get retryable failure, not successful ACK. Exact retry reconciles the
  // same state/history commit and does not manufacture a second revision.
  const exec = DatabaseSync.prototype.exec;
  let injected = false;
  DatabaseSync.prototype.exec = function(sql) {
    const result = exec.call(this, sql);
    if (sql === 'COMMIT' && !injected) {
      injected = true;
      throw new Error('COMMIT_RESPONSE_LOST');
    }
    return result;
  };
  try {
    assert.equal((await post(gateway.origin, `${path}/observations`, siteMaterial, running)).status, 503);
    assert.equal(gateway.pending(), 1);
  } finally { DatabaseSync.prototype.exec = exec; }
  assert.equal((await post(gateway.origin, `${path}/observations`, siteMaterial, running)).status, 200);
  assert.equal(gateway.pending(), 0, 'later dispatch reply settles its already accepted dispatch');
  await completion;
  assert.equal(gateway.pending(), 0);
  const before = store.inspectState(request, control);
  assert.equal(before[0], 2);
  assert.equal((await post(gateway.origin, `${path}/observations`, siteMaterial, accepted)).status, 200);
  assert.deepEqual(store.inspectState(request, control), before);
  await gateway.close();
  store.close();
  store = openSqliteCoordinatorDispatchJournal(storeRoot, {coordinatorAuthority: 'coordinator-a'});
  owner = createOwner();
  gateway = await start();
  for (const body of [accepted, running, runningStatus]) {
    assert.equal((await post(gateway.origin, `${path}/observations`, siteMaterial, body)).status, 200);
  }
  assert.deepEqual(store.inspectState(request, control), before);
  assert.equal((await post(gateway.origin, `${path}/observations`, siteMaterial, unadmitted)).status, 409);
  const conflicting = JSON.parse(accepted);
  conflicting.state[0] = 1;
  const collision = await post(gateway.origin, `${path}/observations`, siteMaterial, JSON.stringify(conflicting));
  assert.equal(collision.status, 409);
  assert.equal(JSON.parse(collision.body).issue, 'StateCollision');
  assert.equal((await post(gateway.origin,
    '/v1/sites/site-a/generations/2/outbound/observations', foreignMaterial, accepted)).status, 409);
  const checked = receiverCalls;
  assert.equal((await post(gateway.origin, `${path}/observations`, foreignMaterial, accepted)).status, 404);
  assert.equal(receiverCalls, checked);
  assert.deepEqual(store.inspectState(request, control), before);
  assert.equal(gateway.pending(), 0);
  assert.equal(dispatchCalls, 1);
});

function dispatch(overrides = {}) {
  return control.prepare({
    coordinatorAuthority: 'coordinator-a',
    runDefinitionCid: cid('0'),
    taskKey: 'task-a',
    taskAttempt: 1,
    dispatchId: 'dispatch-outbound-a',
    siteKey: 'site-a',
    siteGeneration: 1,
    runtimeBundleCid: cid('a'),
    connectorRegistration: 'local',
    connectorRevision: 'local/1',
    strategyRevision: 'strategy/1',
    inputBindingCid:
      'sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a',
    obligationsCid: cid('2'),
    budgetCid: cid('3'),
    evidenceIssuerCapabilityCid: cid('b'),
    grantCid: cid('4'),
    ...overrides,
  });
}

function retainedOutputFixture(request, suffix = 'durable') {
  const intentConfiguration = {
    storeAuthorityCid: cid('5'),
    publicationAttemptCid: cid('6'),
    resultDefinitionCid: cid('7'),
    orderingEvidenceCid: cid('8'),
    coordinatorAuthority: 'coordinator-a',
    transferAttemptId: `transfer-${suffix}`,
    transferRoute: 'direct',
    destinationSite: 'site-b',
    destinationSiteGeneration: 2,
    transferMaxBytes: 1024n,
    transferExpiresAtMilliseconds: 2_000_000_000_000n,
    sourceGrantCid: cid('9'),
    destinationGrantCid: cid('c'),
    routeCapabilityCid: cid('d'),
    transferOrigin: 'https://transfer.example.invalid/output',
  };
  const intent = control.prepareOutputIntent(request, intentConfiguration);
  const materialGeneration = cid('e');
  const physicalManifest = {
    version: 'actql-managed-physical-manifest/0.1',
    schemaContractCid: cid('1'),
    viewContractCid: cid('2'),
    codecContractCid: cid('3'),
    rowCount: 2,
    chunks: [{cid: cid('a'), byteLength: 12n, rowCount: 2}],
  };
  const payloadRequest = control.preparePublicationPayload({
    storeAuthorityCid: intentConfiguration.storeAuthorityCid,
    publicationAttemptCid: intentConfiguration.publicationAttemptCid,
    materialGenerationCid: materialGeneration,
    resultDefinitionCid: intentConfiguration.resultDefinitionCid,
    logicalRelationCid: physicalManifest.viewContractCid,
    resultSchemaCid: physicalManifest.schemaContractCid,
    orderingEvidenceCid: intentConfiguration.orderingEvidenceCid,
    durableCodecCid: physicalManifest.codecContractCid,
    maxBytes: 12n,
    rowCount: 2n,
  });
  const transferRequest = transferControl.prepare({
    coordinatorAuthority: 'coordinator-a',
    transferAttemptId: intentConfiguration.transferAttemptId,
    route: 'direct',
    sourceSite: 'site-a',
    sourceSiteGeneration: 1,
    destinationSite: 'site-b',
    destinationSiteGeneration: 2,
    sourceMaterialGeneration: materialGeneration,
    physicalManifest,
    limits: {
      maxChunks: 4,
      maxManifestBytes: 4096,
      maxReferencedBytes: 12n,
    },
    capacityBytes: 1024n,
    expiresAtMilliseconds: 2_000_000_000_000n,
    sourceGrantCid: cid('9'),
    destinationGrantCid: cid('c'),
    routeCapabilityCid: cid('d'),
  });
  let transferRecord = transferControl.open(transferRequest);
  transferRecord = transferControl.commitTransition(
    transferControl.prepareStart(transferRecord),
    true,
  );
  transferRecord = transferControl.commitTransition(
    transferControl.prepareSourceSettled(transferRecord, true, false),
    true,
  );
  transferRecord = transferControl.commitTransition(
    transferControl.prepareDestinationCommit(transferRecord),
    true,
  );
  return Object.freeze({
    intent,
    payloadRequest,
    transferRequest,
    transferRecord,
  });
}

test('outbound gateway admits one exact retained-output result', async t => {
  await mkdir(scratch, {recursive: true});
  const root = await mkdtemp(join(scratch, 'outbound-output-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const certificates_ = await certificates(root);
  let coordinator;
  const gateway = await startHttpsOutboundSiteGateway({
    key: certificates_.serverKey,
    cert: certificates_.serverCertificate,
    ca: certificates_.ca,
    siteAuthorities: new Map([[
      certificates_.siteFingerprint,
      {siteKey: 'site-a', siteGeneration: 1},
    ]]),
    control,
    receiveObservation: value => coordinator.receiveObservation(value),
  });
  t.after(() => gateway.close());
  const request = dispatch({dispatchId: 'dispatch-output'});
  const store = openSqliteCoordinatorDispatchJournal(join(root, 'coordinator'), {
    coordinatorAuthority: 'coordinator-a',
  });
  t.after(() => store.close());
  coordinator = createRemoteSiteCoordinator({authorization: remoteAuthorization,
    control, transferControl, journal: control.createCoordinatorJournal('coordinator-a'), store,
    send: async () => ({revision: 0, state: [0, 0, 0, 0, 0]}), output: gateway.output});
  await coordinator.dispatch({dispatch: request});
  const intentConfiguration = {
    storeAuthorityCid: cid('5'),
    publicationAttemptCid: cid('6'),
    resultDefinitionCid: cid('7'),
    orderingEvidenceCid: cid('8'),
    coordinatorAuthority: 'coordinator-a',
    transferAttemptId: 'transfer-output',
    transferRoute: 'direct',
    destinationSite: 'site-b',
    destinationSiteGeneration: 2,
    transferMaxBytes: 1024n,
    transferExpiresAtMilliseconds: 2_000_000_000_000n,
    sourceGrantCid: cid('9'),
    destinationGrantCid: cid('c'),
    routeCapabilityCid: cid('d'),
    transferOrigin: 'https://transfer.example.invalid/output',
  };
  const intent = control.prepareOutputIntent(request, intentConfiguration);
  const materialGeneration = cid('e');
  const physicalManifest = {
    version: 'actql-managed-physical-manifest/0.1',
    schemaContractCid: cid('1'),
    viewContractCid: cid('2'),
    codecContractCid: cid('3'),
    rowCount: 2,
    chunks: [{cid: cid('a'), byteLength: 12n, rowCount: 2}],
  };
  const limits = {
    maxChunks: 4,
    maxManifestBytes: 4096,
    maxReferencedBytes: 12n,
  };
  const payloadRequest = control.preparePublicationPayload({
    storeAuthorityCid: intentConfiguration.storeAuthorityCid,
    publicationAttemptCid: intentConfiguration.publicationAttemptCid,
    materialGenerationCid: materialGeneration,
    resultDefinitionCid: intentConfiguration.resultDefinitionCid,
    logicalRelationCid: physicalManifest.viewContractCid,
    resultSchemaCid: physicalManifest.schemaContractCid,
    orderingEvidenceCid: intentConfiguration.orderingEvidenceCid,
    durableCodecCid: physicalManifest.codecContractCid,
    maxBytes: 12n,
    rowCount: 2n,
  });
  const transferRequest = transferControl.prepare({
    coordinatorAuthority: 'coordinator-a',
    transferAttemptId: 'transfer-output',
    route: 'direct',
    sourceSite: 'site-a',
    sourceSiteGeneration: 1,
    destinationSite: 'site-b',
    destinationSiteGeneration: 2,
    sourceMaterialGeneration: materialGeneration,
    physicalManifest,
    limits,
    capacityBytes: 1024n,
    expiresAtMilliseconds: 2_000_000_000_000n,
    sourceGrantCid: cid('9'),
    destinationGrantCid: cid('c'),
    routeCapabilityCid: cid('d'),
  });
  let transferRecord = transferControl.open(transferRequest);
  transferRecord = transferControl.commitTransition(
    transferControl.prepareStart(transferRecord),
    true,
  );
  transferRecord = transferControl.commitTransition(
    transferControl.prepareSourceSettled(transferRecord, true, false),
    true,
  );
  transferRecord = transferControl.commitTransition(
    transferControl.prepareDestinationCommit(transferRecord),
    true,
  );
  const measurement = control.prepareManagedOutputMeasurement(Object.freeze({
    rowCount: 2,
    admissionNodes: 0,
    admissionTextBytes: 0,
    admissionWork: 0,
    columnRows: Object.freeze([2]),
    columnBytes: Object.freeze([12]),
    columnNodes: Object.freeze([2]),
    columnMaxValueBytes: Object.freeze([6]),
    columnNullRows: Object.freeze([0]),
    columnAdmittedDepths: Object.freeze([10]),
  }));
  const subject = control.prepareManagedOutputSubject(
    request,
    Object.freeze({
      materialGeneration,
      managedProfileCid: cid('4'),
      resultSchemaCid: physicalManifest.schemaContractCid,
      logicalViewCid: physicalManifest.viewContractCid,
      representationCodecCid: physicalManifest.codecContractCid,
      physicalManifestCid: physicalCid(
        transferControl.manifestJson(transferRequest),
      ),
      rowCount: 2,
      retainedBytes: 12n,
    }),
    measurement,
    control.outputHoldingEvidenceIdentity(request, materialGeneration, 12n),
  );
  const planning = gateway.plan({
    dispatch: request,
    intent,
    subject,
    ...limits,
  });
  const path = '/v1/sites/site-a/generations/1/outbound';
  const siteMaterial = {
    ca: certificates_.ca,
    cert: certificates_.siteCertificate,
    key: certificates_.siteKey,
  };
  const planPoll = await post(gateway.origin, `${path}/poll`, siteMaterial);
  const planOutput = control.admitPollOutputPlan(planPoll.body);
  const site = runtime.siteControl.create({
    key: 'site-a',
    generation: 1,
    runtimeRevision: cid('a'),
    maxConcurrentOperations: 4,
    maxConcurrentTransfers: 4,
    maxRetainedBytes: 1_048_576n,
    maxExecutionBytes: 1_048_576n,
  });
  const siteStore = openSqliteDispatchJournal(join(root, 'plan-site'), {
    siteKey: 'site-a',
    siteGeneration: 1,
    runtimeRevision: cid('a'),
  });
  t.after(() => siteStore.close());
  const acceptedRecord = siteStore.accept(
    control.prepareAdmission(control.createJournal(site), request),
    request,
    control,
  );
  const wrongOperation = await post(
    gateway.origin,
    `${path}/observations`,
    siteMaterial,
    control.replyJson(acceptedRecord),
  );
  // It is a valid durable dispatch observation, but cannot settle the Plan.
  assert.equal(wrongOperation.status, 200);
  assert.equal(gateway.pending(), 1);
  const plan = control.prepareOutputPlan(
    planOutput,
    subject,
    payloadRequest,
    transferRequest,
  );
  const planReply = await post(
    gateway.origin,
    `${path}/observations`,
    siteMaterial,
    control.outputPlanJson(plan),
  );
  assert.equal(planReply.status, 200);
  const planned = await planning;
  assert.equal(
    control.publicationPayloadJson(planned.payloadRequest),
    control.publicationPayloadJson(payloadRequest),
  );
  assert.equal(
    transferControl.identity(planned.transferRequest),
    transferControl.identity(transferRequest),
  );
  const completion = coordinator.output({
    dispatch: request,
    intent,
    payloadRequest,
    transferRequest,
  });
  const retry = coordinator.output({
    dispatch: request,
    intent,
    payloadRequest,
    transferRequest,
  });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(gateway.pending(), 1);
  const polled = await post(gateway.origin, `${path}/poll`, siteMaterial);
  assert.equal(polled.status, 200);
  const output = control.admitPollOutput(polled.body);
  const payloadDigest = cid('f');
  const outputResult = control.prepareOutputResult(
    output,
    payloadRequest,
    payloadDigest,
    transferRecord,
  );
  const altered = await post(
    gateway.origin,
    `${path}/observations`,
    siteMaterial,
    control.outputResultJson(outputResult).replace(
      transferControl.identity(transferRequest),
      cid('0'),
    ),
  );
  assert.notEqual(altered.status, 200);
  assert.equal(gateway.pending(), 1);
  const observed = await post(
    gateway.origin,
    `${path}/observations`,
    siteMaterial,
    control.outputResultJson(outputResult),
  );
  assert.equal(observed.status, 200);
  const [first, second] = await Promise.all([completion, retry]);
  assert.deepEqual(first, second);
  assert.equal(first.payloadDigest, payloadDigest);
  assert.equal(first.transferRequestCid, transferControl.identity(transferRequest));
  assert.equal(first.transferRevision, 3);
  assert.equal(control.admitOutputReportReply(observed.body, outputResult), true);
  const inspectOutput = () => {
    const journal = control.createCoordinatorJournal('coordinator-a');
    store.recoverJournal(journal, control);
    return store.inspectOutput(store.recoverOutputs(journal, control, transferControl)[0].record, control);
  };
  const beforeReplay = inspectOutput();
  const replayed = await post(gateway.origin, `${path}/observations`, siteMaterial,
    control.outputResultJson(outputResult));
  assert.equal(replayed.status, 200);
  assert.equal(replayed.body, observed.body);
  assert.deepEqual(inspectOutput(), beforeReplay);
  assert.equal(gateway.pending(), 0);
});

test('outbound gateway durably dispatches without an inbound Site listener',
  async t => {
    await mkdir(scratch, {recursive: true});
    const root = await mkdtemp(join(scratch, 'outbound-gateway-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const certificates_ = await certificates(root);
    const gateway = await startHttpsOutboundSiteGateway({
      key: certificates_.serverKey,
      cert: certificates_.serverCertificate,
      ca: certificates_.ca,
      siteAuthorities: new Map([[
        certificates_.siteFingerprint,
        {siteKey: 'site-a', siteGeneration: 1},
      ]]),
      control,
    });
    t.after(() => gateway.close());
    const coordinatorStore = openSqliteCoordinatorDispatchJournal(
      join(root, 'coordinator'),
      {coordinatorAuthority: 'coordinator-a'},
    );
    t.after(() => coordinatorStore.close());
    const coordinator = createRemoteSiteCoordinator({
      authorization: remoteAuthorization,
      control,
      journal: control.createCoordinatorJournal('coordinator-a'),
      store: coordinatorStore,
      send: gateway.dispatch,
      query: gateway.query,
      cancel: async () => {
        throw Object.assign(new Error('OutboundCancelUnsupported'), {
          code: 'OutboundCancelUnsupported',
        });
      },
    });
    const request = dispatch();
    const completion = coordinator.dispatch({
      dispatch: request,
      inputBindingBody: '{}',
    });
    // The Run owner's authorization decision precedes the durable intent.
    for (let turn = 0; turn < 100 && gateway.pending() === 0; turn++) {
      await new Promise(resolve => setImmediate(resolve));
    }
    assert.equal(gateway.pending(), 1);
    const path = '/v1/sites/site-a/generations/1/outbound';
    const siteMaterial = {
      ca: certificates_.ca,
      cert: certificates_.siteCertificate,
      key: certificates_.siteKey,
    };
    const polled = await post(gateway.origin, `${path}/poll`, siteMaterial);
    assert.equal(polled.status, 200);
    const envelope = control.admitPollDispatch(polled.body);
    const received = control.pollDispatchRequest(envelope);
    assert.equal(control.identity(received), control.identity(request));
    assert.equal(control.pollDispatchBindingBody(envelope), '{}');
    const altered = await post(
      gateway.origin,
      `${path}/observations`,
      siteMaterial,
      '{"dispatch_request_cid":"sha256:' + 'f'.repeat(64) + '"}',
    );
    assert.equal(altered.status, 404);
    assert.equal(gateway.pending(), 1);

    const site = runtime.siteControl.create({
      key: 'site-a',
      generation: 1,
      runtimeRevision: cid('a'),
      maxConcurrentOperations: 4,
      maxConcurrentTransfers: 4,
      maxRetainedBytes: 1_048_576n,
      maxExecutionBytes: 1_048_576n,
    });
    const siteJournal = control.createJournal(site);
    const siteStore = openSqliteDispatchJournal(join(root, 'site'), {
      siteKey: 'site-a',
      siteGeneration: 1,
      runtimeRevision: cid('a'),
    });
    t.after(() => siteStore.close());
    let siteAcceptCount = 0;
    siteAcceptCount++;
    const record = siteStore.accept(
      control.prepareAdmission(siteJournal, received),
      received,
      control,
    );
    const observed = await post(
      gateway.origin,
      `${path}/observations`,
      siteMaterial,
      control.replyJson(record),
    );
    assert.equal(observed.status, 200);
    assert.equal(gateway.pending(), 1);
    siteStore.advance(control.prepareProvisioning(
      record,
      control.registerExecutionCapability(Object.freeze({
        site,
        runtimeBundleCid: cid('a'),
        connectorRegistration: 'local',
        connectorRevision: 'local/1',
        strategyRevision: 'strategy/1',
        operationCapabilityCid: cid('4'),
      })),
    ), record, control);
    siteStore.advance(control.prepareExecution(record), record, control);
    siteStore.advance(control.prepareSettled(record), record, control);
    const terminal = await post(
      gateway.origin,
      `${path}/observations`,
      siteMaterial,
      control.statusJson(record, undefined, undefined, undefined),
    );
    assert.equal(terminal.status, 200);
    const result = await completion;
    assert.equal(result.dispatchRequestCid, control.identity(request));
    assert.deepEqual(result.state, [3, 0, 0, 0, 0]);
    assert.equal(gateway.pending(), 0);
    assert.equal(coordinatorStore.contains(request, control), true);

    const queryCompletion = gateway.query({dispatch: request});
    const queryPoll = await post(
      gateway.origin,
      `${path}/poll`,
      siteMaterial,
    );
    assert.equal(queryPoll.status, 200);
    const queryEnvelope = JSON.parse(queryPoll.body);
    assert.equal(queryEnvelope.version, 'actql-remote-poll-query/0.1');
    const queried = control.admitJson(
      queryEnvelope.request_json,
      queryEnvelope.dispatch_request_cid,
    );
    assert.equal(control.identity(queried), control.identity(request));
    const queryObservation = await post(
      gateway.origin,
      `${path}/observations`,
      siteMaterial,
      control.statusJson(record, undefined, undefined, undefined),
    );
    assert.equal(queryObservation.status, 200);
    const queryResult = await queryCompletion;
    assert.equal(queryResult.dispatchRequestCid, control.identity(request));
    assert.deepEqual(queryResult.state, [3, 0, 0, 0, 0]);
    assert.equal(siteAcceptCount, 1);
    assert.equal(gateway.pending(), 0);

    const terminalCompletion = gateway.query({dispatch: request});
    const terminalPoll = await post(
      gateway.origin,
      `${path}/poll`,
      siteMaterial,
    );
    assert.equal(terminalPoll.status, 200);
    assert.equal(
      JSON.parse(terminalPoll.body).version,
      'actql-remote-poll-query/0.1',
    );
    const terminalObservation = await post(
      gateway.origin,
      `${path}/observations`,
      siteMaterial,
      control.statusJson(record, undefined, undefined, undefined),
    );
    assert.equal(terminalObservation.status, 200);
    assert.deepEqual((await terminalCompletion).state, [3, 0, 0, 0, 0]);
    assert.equal(siteAcceptCount, 1);

    let releaseFinished = false;
    const releaseCompletion = gateway.release({dispatch: request}).then(value => {
      releaseFinished = true;
      return value;
    }, error => error);
    const releasePoll = await post(
      gateway.origin,
      `${path}/poll`,
      siteMaterial,
    );
    assert.equal(releasePoll.status, 200);
    assert.equal(
      JSON.parse(releasePoll.body).version,
      'actql-remote-poll-release/0.1',
    );
    // A later query has not been offered to the Site. The response to the
    // already-delivered release must still complete the release waiter first.
    let lateQueryFinished = false;
    const lateQuery = gateway.query({dispatch: request}).then(value => {
      lateQueryFinished = true;
      return value;
    }, error => error);
    siteStore.advance(control.prepareRelease(record), record, control);
    siteStore.advance(control.prepareReleased(record), record, control);
    const releaseObservation = await post(
      gateway.origin,
      `${path}/observations`,
      siteMaterial,
      control.statusJson(record, undefined, undefined, undefined),
    );
    assert.equal(releaseObservation.status, 200);
    // Waiters settle before the HTTP ACK; no sleep or timeout is needed to
    // distinguish an uncompleted release from the physical released state.
    assert.equal(releaseFinished, true);
    assert.equal(lateQueryFinished, false);
    assert.deepEqual((await releaseCompletion).state, [3, 0, 2, 0, 0]);
    assert.equal(siteAcceptCount, 1);
    assert.equal(gateway.pending(), 1);
    const lateQueryPoll = await post(gateway.origin, `${path}/poll`, siteMaterial);
    assert.equal(lateQueryPoll.status, 200);
    assert.equal(JSON.parse(lateQueryPoll.body).version,
      'actql-remote-poll-query/0.1');
    assert.equal((await post(gateway.origin, `${path}/observations`, siteMaterial,
      control.statusJson(record, undefined, undefined, undefined))).status, 200);
    assert.equal(lateQueryFinished, true);
    assert.deepEqual((await lateQuery).state, [3, 0, 2, 0, 0]);
    assert.equal(gateway.pending(), 0);

    const unseen = dispatch({
      dispatchId: 'dispatch-outbound-unseen',
      taskAttempt: 2,
    });
    const unseenCompletion = gateway.query({dispatch: unseen});
    const unseenResult = unseenCompletion.catch(error => error);
    const unseenPoll = await post(
      gateway.origin,
      `${path}/poll`,
      siteMaterial,
    );
    assert.equal(unseenPoll.status, 200);
    assert.equal(
      JSON.parse(unseenPoll.body).version,
      'actql-remote-poll-query/0.1',
    );
    const notSeen = await post(
      gateway.origin,
      `${path}/observations`,
      siteMaterial,
      control.pollNotSeenJson(unseen),
    );
    assert.equal(notSeen.status, 200);
    const unseenError = await unseenResult;
    assert.equal(unseenError.code, 'RemoteDispatchNotSeen');
    assert.equal(unseenError.notSeenBody, control.pollNotSeenJson(unseen));
    assert.equal(siteAcceptCount, 1);
    assert.equal(gateway.pending(), 0);

    const retransmitFirst = gateway.dispatch({
      dispatch: request,
      inputBindingBody: '{}',
    });
    const retransmitSecond = gateway.dispatch({
      dispatch: request,
      inputBindingBody: '{}',
    });
    assert.throws(
      () => gateway.dispatch({
        dispatch: request,
        inputBindingBody: '{"changed":true}',
      }),
      {code: 'OutboundDispatchBindingCollision'},
    );
    assert.equal(gateway.pending(), 1);
    const retransmitPoll = await post(
      gateway.origin,
      `${path}/poll`,
      siteMaterial,
    );
    const retransmitEnvelope = control.admitPollDispatch(
      retransmitPoll.body,
    );
    const retransmitRequest = control.pollDispatchRequest(
      retransmitEnvelope,
    );
    siteAcceptCount++;
    const retransmitRecord = siteStore.accept(
      control.prepareAdmission(siteJournal, retransmitRequest),
      retransmitRequest,
      control,
    );
    const retransmitObservation = await post(
      gateway.origin,
      `${path}/observations`,
      siteMaterial,
      control.replyJson(retransmitRecord),
    );
    assert.equal(retransmitObservation.status, 200);
    await Promise.all([retransmitFirst, retransmitSecond]);
    assert.equal(siteAcceptCount, 2);
    assert.equal(gateway.pending(), 0);

    const collision = dispatch({connectorRevision: 'local/2'});
    const collisionWaiter = gateway.dispatch({
      dispatch: collision,
      inputBindingBody: '{}',
    });
    void collisionWaiter.catch(() => {});
    const collisionPoll = await post(
      gateway.origin,
      `${path}/poll`,
      siteMaterial,
    );
    const collisionEnvelope = control.admitPollDispatch(collisionPoll.body);
    const collisionRequest = control.pollDispatchRequest(collisionEnvelope);
    assert.throws(
      () => siteStore.accept(
        control.prepareAdmission(siteJournal, collisionRequest),
        collisionRequest,
        control,
      ),
      {code: 'MoonBitHostFailure'},
    );

    const foreign = await post(gateway.origin, `${path}/poll`, {
      ca: certificates_.ca,
      cert: certificates_.foreignCertificate,
      key: certificates_.foreignKey,
    });
    assert.equal(foreign.status, 404);
  });

test('Coordinator restores a committed output without repeating transport',
  async t => {
    await mkdir(scratch, {recursive: true});
    const root = await mkdtemp(join(scratch, 'outbound-output-journal-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const certificates_ = await certificates(root);
    let receiver;
    const gateway = await startHttpsOutboundSiteGateway({
      key: certificates_.serverKey,
      cert: certificates_.serverCertificate,
      ca: certificates_.ca,
      siteAuthorities: new Map([[
        certificates_.siteFingerprint,
        {siteKey: 'site-a', siteGeneration: 1},
      ]]),
      control,
      receiveObservation: value => receiver.receiveObservation(value),
    });
    t.after(() => gateway.close());
    const storeRoot = join(root, 'coordinator');
    const store = openSqliteCoordinatorDispatchJournal(storeRoot, {
      coordinatorAuthority: 'coordinator-a',
    });
    const request = dispatch({dispatchId: 'dispatch-output-journal'});
    const fixture = retainedOutputFixture(request, 'journal');
    const coordinator = createRemoteSiteCoordinator({
      authorization: remoteAuthorization,
      control,
      transferControl,
      journal: control.createCoordinatorJournal('coordinator-a'),
      store,
      send: async () => Object.freeze({
        revision: 0,
        state: [0, 0, 0, 0, 0],
      }),
      output: gateway.output,
    });
    receiver = coordinator;
    await coordinator.dispatch({dispatch: request});
    const outputRequest = {
      dispatch: request,
      intent: fixture.intent,
      payloadRequest: fixture.payloadRequest,
      transferRequest: fixture.transferRequest,
    };
    const completion = coordinator.output(outputRequest);
    const concurrentRetry = coordinator.output(outputRequest);
    const path = '/v1/sites/site-a/generations/1/outbound';
    const siteMaterial = {
      ca: certificates_.ca,
      cert: certificates_.siteCertificate,
      key: certificates_.siteKey,
    };
    const polled = await post(gateway.origin, `${path}/poll`, siteMaterial);
    const output = control.admitPollOutput(polled.body);
    const result = control.prepareOutputResult(
      output,
      fixture.payloadRequest,
      cid('f'),
      fixture.transferRecord,
    );
    const observed = await post(
      gateway.origin,
      `${path}/observations`,
      siteMaterial,
      control.outputResultJson(result),
    );
    assert.equal(observed.status, 200);
    const [first, retried] = await Promise.all([
      completion,
      concurrentRetry,
    ]);
    assert.deepEqual(retried, first);
    assert.equal(first.resultCid, control.outputResultIdentity(result));
    store.close();

    const reopenedStore = openSqliteCoordinatorDispatchJournal(storeRoot, {
      coordinatorAuthority: 'coordinator-a',
    });
    t.after(() => reopenedStore.close());
    let repeated = false;
    const reopened = createRemoteSiteCoordinator({
      authorization: remoteAuthorization,
      control,
      transferControl,
      journal: control.createCoordinatorJournal('coordinator-a'),
      store: reopenedStore,
      output: async () => {
        repeated = true;
        throw new Error('output transport must not repeat');
      },
    });
    receiver = reopened;
    const replayed = await post(gateway.origin, `${path}/observations`, siteMaterial,
      control.outputResultJson(result));
    assert.equal(replayed.status, 200);
    assert.equal(replayed.body, observed.body);
    assert.equal(reopened.recoveredOutputs.length, 1);
    const restored = await reopened.output({
      dispatch: request,
      intent: fixture.intent,
      payloadRequest: fixture.payloadRequest,
      transferRequest: fixture.transferRequest,
    });
    assert.deepEqual(restored, first);
    assert.equal(repeated, false);
  });

test('exact query is delivered and answered ahead of an unresolved dispatch',
  {timeout: 30_000}, async t => {
    await mkdir(scratch, {recursive: true});
    const root = await mkdtemp(join(scratch, 'outbound-query-priority-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const certificates_ = await certificates(root);
    const gateway = await startHttpsOutboundSiteGateway({
      key: certificates_.serverKey,
      cert: certificates_.serverCertificate,
      ca: certificates_.ca,
      siteAuthorities: new Map([[
        certificates_.siteFingerprint,
        {siteKey: 'site-a', siteGeneration: 1},
      ]]),
      control,
    });
    t.after(() => gateway.close());
    const path = '/v1/sites/site-a/generations/1/outbound';
    const siteMaterial = {
      ca: certificates_.ca,
      cert: certificates_.siteCertificate,
      key: certificates_.siteKey,
    };
    const site = runtime.siteControl.create({
      key: 'site-a', generation: 1, runtimeRevision: cid('a'),
      maxConcurrentOperations: 4, maxConcurrentTransfers: 4,
      maxRetainedBytes: 1_048_576n, maxExecutionBytes: 1_048_576n,
    });
    const siteJournal = control.createJournal(site);
    const siteStore = openSqliteDispatchJournal(join(root, 'site'), {
      siteKey: 'site-a', siteGeneration: 1, runtimeRevision: cid('a'),
    });
    t.after(() => siteStore.close());

    for (const acceptanceAcknowledged of [false, true]) {
      const request = dispatch({
        dispatchId: `dispatch-query-priority-${acceptanceAcknowledged}`,
        taskAttempt: acceptanceAcknowledged ? 2 : 1,
      });
      const dispatched = gateway.dispatch({dispatch: request,
        inputBindingBody: '{}'}).catch(error => error);
      const firstOffer = await post(gateway.origin, `${path}/poll`, siteMaterial);
      assert.equal(firstOffer.status, 200);
      if (!acceptanceAcknowledged) {
        const notSeen = gateway.query({dispatch: request}).catch(error => error);
        const queryOffer = await post(gateway.origin, `${path}/poll`, siteMaterial);
        assert.equal(JSON.parse(queryOffer.body).version,
          'actql-remote-poll-query/0.1');
        assert.equal((await post(gateway.origin, `${path}/observations`,
          siteMaterial, control.pollNotSeenJson(request))).status, 200);
        assert.equal((await notSeen).code, 'RemoteDispatchNotSeen');
        assert.equal(gateway.pending(), 1);
        const originalOffer = await post(gateway.origin, `${path}/poll`, siteMaterial);
        assert.equal(originalOffer.body, firstOffer.body);
      }
      const accepted = siteStore.accept(
        control.prepareAdmission(siteJournal, request), request, control);
      if (acceptanceAcknowledged) {
        assert.equal((await post(gateway.origin, `${path}/observations`,
          siteMaterial, control.replyJson(accepted))).status, 200);
      }
      const originalRevision = control.revision(accepted);
      // The old dispatch remains pending across multiple queries. A latest
      // state/status response must complete the query, not steal it for that
      // older waiter. No sleep or accepted-as-terminal expectation is used.
      for (let pass = 0; pass < 3; pass++) {
        let queryFinished = false;
        const queried = gateway.query({dispatch: request}).then(result => {
          queryFinished = true;
          return result;
        }, error => error);
        assert.equal(gateway.pending(), 2);
        const offered = await post(gateway.origin, `${path}/poll`, siteMaterial);
        assert.equal(offered.status, 200);
        assert.equal(JSON.parse(offered.body).version,
          'actql-remote-poll-query/0.1');
        assert.equal(JSON.parse(offered.body).dispatch_request_cid,
          control.identity(request));
        if (!acceptanceAcknowledged && pass === 0) {
          // Query admission requires a status response. A delayed acceptance
          // reply still falls back to the exact dispatch waiter; it must not
          // complete or remove the query.
          assert.equal((await post(gateway.origin, `${path}/observations`,
            siteMaterial, control.replyJson(accepted))).status, 200);
          assert.equal(queryFinished, false);
          assert.equal(gateway.pending(), 2);
        }
        const foreign = dispatch({dispatchId: 'unrelated-query-response'});
        assert.equal((await post(gateway.origin, `${path}/observations`,
          siteMaterial, control.pollNotSeenJson(foreign))).status, 404);
        assert.equal(gateway.pending(), 2);
        assert.equal((await post(gateway.origin, `${path}/observations`,
          siteMaterial, control.statusJson(accepted,
            undefined, undefined, undefined))).status, 200);
        // Routing settles the waiter before sending the HTTP ACK. Checking
        // here detects a stolen reply without waiting for a test timeout.
        assert.equal(queryFinished, true);
        const result = await queried;
        assert.equal(result.dispatchRequestCid, control.identity(request));
        assert.deepEqual(result.state, [0, 0, 0, 0, 0]);
        assert.equal(control.revision(accepted), originalRevision);
        assert.equal(gateway.pending(), 1);
      }
      const unrelated = dispatch({dispatchId: `fifo-${acceptanceAcknowledged}`,
        taskAttempt: acceptanceAcknowledged ? 4 : 3});
      const unrelatedSend = gateway.dispatch({dispatch: unrelated,
        inputBindingBody: '{}'}).catch(error => error);
      const queried = gateway.query({dispatch: request}).catch(error => error);
      const fifoOffer = await post(gateway.origin, `${path}/poll`, siteMaterial);
      assert.equal(JSON.parse(fifoOffer.body).version,
        'actql-remote-poll-dispatch/0.1');
      assert.equal(control.identity(control.pollDispatchRequest(
        control.admitPollDispatch(fifoOffer.body))), control.identity(unrelated));
      gateway.withdraw({dispatch: unrelated});
      assert.equal((await unrelatedSend).code, 'RemoteDispatchWithdrawn');
      assert.equal(JSON.parse((await post(gateway.origin, `${path}/poll`,
        siteMaterial)).body).version, 'actql-remote-poll-query/0.1');
      assert.equal((await post(gateway.origin, `${path}/observations`, siteMaterial,
        control.statusJson(accepted, undefined, undefined, undefined))).status, 200);
      assert.equal((await queried).dispatchRequestCid, control.identity(request));
      // This transport change does not silently drop or complete the original
      // dispatch waiter. Its existing explicit withdrawal path still owns it.
      assert.equal(gateway.withdraw({dispatch: request}), true);
      assert.equal((await dispatched).code, 'RemoteDispatchWithdrawn');
      assert.equal(gateway.pending(), 0);
    }
  });

for (const boundary of ['before poll', 'after poll', 'after lost saved-cancellation reply']) {
  test(`Cancel delivery survives old status ${boundary}`, {timeout: 15_000}, async t => {
    await mkdir(scratch, {recursive: true});
    const root = await mkdtemp(join(scratch, 'cancel-status-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const material = await certificates(root);
    const siteMaterial = {ca: material.ca, cert: material.siteCertificate,
      key: material.siteKey};
    const store = openSqliteCoordinatorDispatchJournal(join(root, 'coordinator'),
      {coordinatorAuthority: 'coordinator-a'});
    t.after(() => store.close());
    let coordinator;
    let observations = 0;
    const gateway = await startHttpsOutboundSiteGateway({
      key: material.serverKey, cert: material.serverCertificate, ca: material.ca,
      siteAuthorities: new Map([[material.siteFingerprint,
        {siteKey: 'site-a', siteGeneration: 1}]]), control,
      receiveObservation: async value => {
        const receipt = await coordinator.receiveObservation(value);
        observations++;
        return receipt;
      },
    });
    t.after(() => gateway.close());
    coordinator = createRemoteSiteCoordinator({authorization: remoteAuthorization,
      control, journal: control.createCoordinatorJournal('coordinator-a'), store,
      send: async () => ({revision: 0, state: [0, 0, 0, 0, 0]})});
    const request = dispatch({dispatchId: `cancel-old-status-${boundary}`});
    await coordinator.dispatch({dispatch: request});
    const site = runtime.siteControl.create({key: 'site-a', generation: 1,
      runtimeRevision: cid('a'), maxConcurrentOperations: 4,
      maxConcurrentTransfers: 4, maxRetainedBytes: 1_048_576n,
      maxExecutionBytes: 1_048_576n});
    const journal = control.createJournal(site);
    const siteStore = openSqliteDispatchJournal(join(root, 'site'),
      {siteKey: 'site-a', siteGeneration: 1, runtimeRevision: cid('a')});
    t.after(() => siteStore.close());
    const record = siteStore.accept(control.prepareAdmission(journal, request), request, control);
    siteStore.advance(control.prepareProvisioning(record,
      control.registerExecutionCapability({site, runtimeBundleCid: cid('a'),
        connectorRegistration: 'local', connectorRevision: 'local/1',
        strategyRevision: 'strategy/1', operationCapabilityCid: cid('4')})), record, control);
    siteStore.advance(control.prepareExecution(record), record, control);
    const oldRunning = control.statusJson(record, undefined, undefined, undefined);
    let completed = false;
    const cancellation = gateway.cancel({dispatch: request}).then(value => {
      completed = true; return value;
    }).catch(error => error);
    const path = '/v1/sites/site-a/generations/1/outbound';
    const expectedEnvelope = control.pollCancelJson(request);
    const poll = () => post(gateway.origin, `${path}/poll`, siteMaterial);
    if (boundary !== 'before poll') {
      assert.equal((await poll()).body, expectedEnvelope);
    }
    assert.equal((await post(gateway.origin, `${path}/observations`,
      siteMaterial, oldRunning)).status, 200);
    assert.equal(observations, 1, 'ordinary status is still durably admitted');
    assert.equal(completed, false, 'old running status cannot complete cancellation');
    assert.equal(gateway.pending(), 1);
    assert.equal((await poll()).body, expectedEnvelope,
      'the exact original Cancel remains available even after a previous offer');

    // The common journal persists a cancellation disposition, but cleanup
    // is still active. Losing this reply cannot discharge delivery custody.
    siteStore.advance(control.prepareCancelled(record), record, control);
    const savedCancellation = control.statusJson(record, undefined, undefined, undefined);
    if (boundary === 'after lost saved-cancellation reply') {
      const lost = await postWithLostAck(gateway.origin, `${path}/observations`,
        siteMaterial, savedCancellation).catch(error => error);
      assert.equal(lost.code, 'ACK_LOST');
    } else {
      assert.equal((await post(gateway.origin, `${path}/observations`,
        siteMaterial, savedCancellation)).status, 200);
    }
    assert.equal(completed, false, 'cancellation persistence is not cleanup completion');
    assert.equal(gateway.pending(), 1);
    assert.equal((await poll()).body, expectedEnvelope);
    const cancelledRevision = control.revision(record);
    assert.equal((await post(gateway.origin, `${path}/observations`,
      siteMaterial, savedCancellation)).status, 200);
    assert.equal(control.revision(record), cancelledRevision);
    assert.equal(completed, false);
    siteStore.advance(control.prepareRelease(record), record, control);
    siteStore.advance(control.prepareReleased(record), record, control);
    const terminal = control.statusJson(record, undefined, undefined, undefined);
    assert.equal((await post(gateway.origin, `${path}/observations`, siteMaterial, terminal)).status, 200);
    assert.deepEqual((await cancellation).state, [5, 0, 2, 0, 0]);
    assert.equal(gateway.pending(), 0);
    assert.equal((await poll()).status, 204);
  });
}

test('outbound cancellation cannot admit work before dispatch', async t => {
  await mkdir(scratch, {recursive: true});
  const root = await mkdtemp(join(scratch, 'outbound-cancel-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const certificates_ = await certificates(root);
  const gateway = await startHttpsOutboundSiteGateway({
    key: certificates_.serverKey,
    cert: certificates_.serverCertificate,
    ca: certificates_.ca,
    siteAuthorities: new Map([[
      certificates_.siteFingerprint,
      {siteKey: 'site-a', siteGeneration: 1},
    ]]),
    control,
  });
  t.after(() => gateway.close());
  const path = '/v1/sites/site-a/generations/1/outbound';
  const siteMaterial = {
    ca: certificates_.ca,
    cert: certificates_.siteCertificate,
    key: certificates_.siteKey,
  };
  const request = dispatch();
  const preAborted = new AbortController();
  const preAbortReason = new Error('pre-aborted');
  preAborted.abort(preAbortReason);
  assert.equal(
    await gateway.dispatch({
      dispatch: request,
      inputBindingBody: '{}',
      signal: preAborted.signal,
    }).catch(error => error),
    preAbortReason,
  );
  assert.equal(
    await gateway.query({
      dispatch: request,
      signal: preAborted.signal,
    }).catch(error => error),
    preAbortReason,
  );
  assert.equal(gateway.pending(), 0);
  assert.equal(
    (await post(gateway.origin, `${path}/poll`, siteMaterial)).status,
    204,
  );

  const first = new AbortController();
  const second = new AbortController();
  const firstWaiter = gateway.dispatch({
    dispatch: request,
    inputBindingBody: '{}',
    signal: first.signal,
  });
  const secondWaiter = gateway.dispatch({
    dispatch: request,
    inputBindingBody: '{}',
    signal: second.signal,
  });
  const survivor = gateway.dispatch({
    dispatch: request,
    inputBindingBody: '{}',
  });
  const firstReason = new Error('first waiter left');
  const secondReason = new Error('second waiter left');
  first.abort(firstReason);
  second.abort(secondReason);
  assert.equal(await firstWaiter.catch(error => error), firstReason);
  assert.equal(await secondWaiter.catch(error => error), secondReason);
  assert.equal(gateway.pending(), 1);

  const polled = await post(gateway.origin, `${path}/poll`, siteMaterial);
  assert.equal(polled.status, 200);
  const envelope = control.admitPollDispatch(polled.body);
  const received = control.pollDispatchRequest(envelope);
  const site = runtime.siteControl.create({
    key: 'site-a',
    generation: 1,
    runtimeRevision: cid('a'),
    maxConcurrentOperations: 4,
    maxConcurrentTransfers: 4,
    maxRetainedBytes: 1_048_576n,
    maxExecutionBytes: 1_048_576n,
  });
  const siteJournal = control.createJournal(site);
  const siteStore = openSqliteDispatchJournal(join(root, 'site'), {
    siteKey: 'site-a',
    siteGeneration: 1,
    runtimeRevision: cid('a'),
  });
  t.after(() => siteStore.close());
  const record = siteStore.accept(
    control.prepareAdmission(siteJournal, received),
    received,
    control,
  );
  const observed = await post(
    gateway.origin,
    `${path}/observations`,
    siteMaterial,
    control.replyJson(record),
  );
  assert.equal(observed.status, 200);
  assert.equal(gateway.pending(), 1);
  siteStore.advance(control.prepareProvisioning(
    record,
    control.registerExecutionCapability(Object.freeze({
      site,
      runtimeBundleCid: cid('a'),
      connectorRegistration: 'local',
      connectorRevision: 'local/1',
      strategyRevision: 'strategy/1',
      operationCapabilityCid: cid('4'),
    })),
  ), record, control);
  siteStore.advance(control.prepareExecution(record), record, control);
  siteStore.advance(control.prepareSettled(record), record, control);
  const terminal = await post(
    gateway.origin,
    `${path}/observations`,
    siteMaterial,
    control.statusJson(record, undefined, undefined, undefined),
  );
  assert.equal(terminal.status, 200);
  assert.equal((await survivor).dispatchRequestCid, control.identity(request));
  assert.equal(gateway.pending(), 0);
});

test('outbound poll waits for work admitted during the idle window', async t => {
  await mkdir(scratch, {recursive: true});
  const root = await mkdtemp(join(scratch, 'outbound-idle-poll-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const certificates_ = await certificates(root);
  const gateway = await startHttpsOutboundSiteGateway({
    key: certificates_.serverKey,
    cert: certificates_.serverCertificate,
    ca: certificates_.ca,
    siteAuthorities: new Map([[
      certificates_.siteFingerprint,
      {siteKey: 'site-a', siteGeneration: 1},
    ]]),
    control,
    idlePollMilliseconds: 1000,
  });
  t.after(() => gateway.close());
  const path = '/v1/sites/site-a/generations/1/outbound';
  const siteMaterial = {
    ca: certificates_.ca,
    cert: certificates_.siteCertificate,
    key: certificates_.siteKey,
  };
  let pollFinished = false;
  const poll = post(gateway.origin, `${path}/poll`, siteMaterial).then(value => {
    pollFinished = true;
    return value;
  });
  await new Promise(resolve => setTimeout(resolve, 25));
  assert.equal(pollFinished, false);
  const request = dispatch();
  const dispatched = gateway.dispatch({
    dispatch: request,
    inputBindingBody: '{}',
  });
  const dispatchedRejection = dispatched.catch(error => error);
  const response = await poll;
  assert.equal(response.status, 200);
  const envelope = control.admitPollDispatch(response.body);
  assert.equal(
    control.identity(control.pollDispatchRequest(envelope)),
    control.identity(request),
  );
  const closed = gateway.close();
  assert.equal(
    (await dispatchedRejection).message,
    'OutboundSiteGatewayClosed',
  );
  await closed;
});

test('Cancel waiter applies the common retirement projection after durable admission',
  {timeout: 15_000}, async t => {
    await mkdir(scratch, {recursive: true});
    const root = await mkdtemp(join(scratch, 'cancel-projection-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const material = await certificates(root);
    const siteMaterial = {ca: material.ca, cert: material.siteCertificate,
      key: material.siteKey};
    const store = openSqliteCoordinatorDispatchJournal(join(root, 'coordinator'),
      {coordinatorAuthority: 'coordinator-a'});
    t.after(() => store.close());
    let owner;
    let admitted = false;
    const projected = [];
    const gateway = await startHttpsOutboundSiteGateway({
      key: material.serverKey, cert: material.serverCertificate, ca: material.ca,
      siteAuthorities: new Map([[material.siteFingerprint,
        {siteKey: 'site-a', siteGeneration: 1}]]),
      control: {...control, responseCanRetireCancellationDelivery() {
        assert.fail('a durable receiver must project its latest owner');
      }},
      receiveObservation: async value => {
        const receipt = await owner.receiveObservation(value);
        admitted = true;
        return receipt;
      },
    });
    t.after(() => gateway.close());
    owner = createRemoteSiteCoordinator({authorization: remoteAuthorization,
      control: {...control, coordinatorCanRetireCancellationDelivery(record) {
        assert.equal(admitted, true, 'durability must precede retirement');
        const value = control.coordinatorCanRetireCancellationDelivery(record);
        projected.push(value);
        return value;
      }}, journal: control.createCoordinatorJournal('coordinator-a'),
      store: {...store, advance(...args) {
        const result = store.advance(...args); admitted = true; return result;
      }}, send: async () => ({revision: 0, state: [0, 0, 0, 0, 0]})});
    const cases = [
      [[6, 0, 2, 0, 0], false], [[5, 0, 1, 0, 0], false],
      [[3, 1, 0, 1, 0], false], [[6, 0, 4, 0, 1], false],
      [[3, 0, 5, 0, 0], false], [[3, 0, 2, 0, 0], true],
      [[4, 0, 2, 0, 0], true], [[5, 0, 2, 0, 0], true],
    ];
    for (const [index, [state, expected]] of cases.entries()) {
      const request = dispatch({dispatchId: `retirement-${index}`, taskAttempt: index + 1});
      await owner.dispatch({dispatch: request});
      let completed = false;
      const waiting = gateway.cancel({dispatch: request}).then(value => {
        completed = true;
        return value;
      }).catch(error => error);
      admitted = false;
      const reply = JSON.stringify({version: 'actql-remote-dispatch-status/0.1',
        dispatch_request_cid: control.identity(request), revision: 1, state,
        evidence: null, subject: null, measurement: null});
      const response = await post(gateway.origin,
        '/v1/sites/site-a/generations/1/outbound/observations', siteMaterial, reply);
      assert.equal(response.status, 200);
      assert.equal(projected.at(-1), expected);
      assert.equal(completed, expected);
      if (expected) assert.deepEqual((await waiting).state, state);
    }
    assert.deepEqual(projected, cases.map(([, expected]) => expected));
  });

// A single physical Site record goes through retained output, release, force
// loss and late cleanup. The transport consumes the same durable history.
// This fixture is not the installed public Effect Host's separate Run path.
for (const boundary of ['already admitted', 'receiver await', 'lost newer commit']) {
test(`integrated Cancel ignores an old released reply after later recovered loss: ${boundary}`,
  {timeout: 15_000}, async t => {
  await mkdir(scratch, {recursive: true});
  const root = await mkdtemp(join(scratch, 'cancel-current-history-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const material = await certificates(root);
  const siteMaterial = {ca: material.ca, cert: material.siteCertificate,
    key: material.siteKey};
  const store = openSqliteCoordinatorDispatchJournal(join(root, 'coordinator'),
    {coordinatorAuthority: 'coordinator-a'});
  t.after(() => store.close());
  let coordinator, gateway, observations = 0, sends = 0, cancellations = 0;
  let pausedWire, resumeReceipt, receiptEntered;
  const receiptHeld = new Promise(resolve => { resumeReceipt = resolve; });
  const entered = new Promise(resolve => { receiptEntered = resolve; });
  t.after(() => resumeReceipt());
  gateway = await startHttpsOutboundSiteGateway({
    key: material.serverKey, cert: material.serverCertificate, ca: material.ca,
    siteAuthorities: new Map([[material.siteFingerprint,
      {siteKey: 'site-a', siteGeneration: 1}]]), control,
    receiveObservation: async value => {
      const receipt = await coordinator.receiveObservation(value);
      observations++;
      if (value.body === pausedWire) { receiptEntered(); await receiptHeld; }
      return receipt;
    }});
  t.after(() => gateway.close());
  coordinator = createRemoteSiteCoordinator({authorization: remoteAuthorization,
    control, journal: control.createCoordinatorJournal('coordinator-a'), store,
    send: value => { sends++; return gateway.dispatch(value); },
    cancel: value => { cancellations++; return gateway.cancel(value); }});
  const request = dispatch({dispatchId: 'integrated-current-cancel'});
  const path = '/v1/sites/site-a/generations/1/outbound';
  const started = coordinator.dispatch({dispatch: request, inputBindingBody: '{}'});
  started.catch(() => {});
  const polled = await post(gateway.origin, `${path}/poll`, siteMaterial);
  assert.equal(polled.status, 200);
  const received = control.pollDispatchRequest(control.admitPollDispatch(polled.body));
  assert.equal(control.identity(received), control.identity(request));
  const site = runtime.siteControl.create({key: 'site-a', generation: 1,
    runtimeRevision: cid('a'), maxConcurrentOperations: 4,
    maxConcurrentTransfers: 4, maxRetainedBytes: 1_048_576n,
    maxExecutionBytes: 1_048_576n});
  const journal = control.createJournal(site);
  const siteStore = openSqliteDispatchJournal(join(root, 'site'),
    {siteKey: 'site-a', siteGeneration: 1, runtimeRevision: cid('a')});
  t.after(() => siteStore.close());
  const record = siteStore.accept(control.prepareAdmission(journal, received),
    received, control);
  siteStore.advance(control.prepareProvisioning(record,
    control.registerExecutionCapability({site, runtimeBundleCid: cid('a'),
      connectorRegistration: 'local', connectorRevision: 'local/1',
      strategyRevision: 'strategy/1', operationCapabilityCid: cid('4')})), record, control);
  siteStore.advance(control.prepareExecution(record), record, control);
  const postStatus = body => post(gateway.origin, `${path}/observations`, siteMaterial, body);
  assert.equal((await postStatus(control.replyJson(record))).status, 200);
  await started;
  const oldRunning = control.statusJson(record, undefined, undefined, undefined);
  siteStore.advance(control.prepareSettled(record), record, control);
  const holding = control.outputHoldingEvidenceIdentity(request, 'integrated-material', 8n);
  siteStore.advance(control.prepareRetained(record, 'integrated-material', holding), record, control);
  const held = control.statusJson(record, undefined, undefined, undefined);
  assert.equal((await postStatus(held)).status, 200);
  assert.equal(control.responseCanRetireCancellationDelivery(
    control.admitResponseJson(held, request, true)), false);
  siteStore.advance(control.prepareRelease(record), record, control);
  siteStore.advance(control.prepareReleased(record), record, control);
  const released = control.statusJson(record, undefined, undefined, undefined);
  assert.equal((await postStatus(released)).status, 200);
  // The Site persists its quarantine then later physical recovery. Only the
  // recovered status reaches the Coordinator; skipped intermediate replies
  // are normal for a disconnected Site and must not restore success.
  siteStore.forceLoss(control.prepareForceLoss(journal, record, true), record, control);
  const quarantined = control.statusJson(record, undefined, undefined, undefined);
  assert.equal(control.responseCanRetireCancellationDelivery(
    control.admitResponseJson(quarantined, request, true)), false);
  siteStore.advance(control.prepareLossRecovery(record), record, control);
  const recovered = control.statusJson(record, undefined, undefined, undefined);
  assert.deepEqual(control.status(record), [6, 1, 5, 0, 0]);
  if (boundary === 'already admitted') {
    assert.equal((await postStatus(recovered)).status, 200);
  }
  assert.equal(control.responseCanRetireCancellationDelivery(
    control.admitResponseJson(recovered, request, true)), false);
  let latest = store.inspectState(request, control);
  let completed = false;
  const cancellation = coordinator.cancel({dispatch: request}).then(value => {
    completed = true; return value;
  }).catch(error => error);
  assert.equal((await post(gateway.origin, `${path}/poll`, siteMaterial)).body,
    control.pollCancelJson(request));
  if (boundary === 'already admitted') {
    assert.equal((await postStatus(oldRunning)).status, 200);
    assert.equal(completed, false);
    assert.deepEqual(store.inspectState(request, control), latest);
    assert.equal((await postStatus(released)).status, 200);
  } else {
    pausedWire = released;
    const oldReply = postStatus(released);
    await entered;
    const exec = DatabaseSync.prototype.exec;
    let injected = false;
    if (boundary === 'lost newer commit') {
      DatabaseSync.prototype.exec = function(sql) {
        const result = exec.call(this, sql);
        if (sql === 'COMMIT' && !injected) {
          injected = true;
          throw new Error('INTEGRATED_NEWER_COMMIT_ACK_LOST');
        }
        return result;
      };
    }
    try {
      assert.equal((await postStatus(recovered)).status,
        boundary === 'lost newer commit' ? 503 : 200);
    } finally { DatabaseSync.prototype.exec = exec; }
    assert.equal(injected, boundary === 'lost newer commit');
    latest = store.inspectState(request, control);
    resumeReceipt();
    assert.equal((await oldReply).status, 200);
    assert.equal(completed, false, 'an overtaken receipt cannot retire delivery');
    if (boundary === 'lost newer commit') {
      assert.equal((await postStatus(recovered)).status, 200);
    }
  }
  assert.deepEqual(store.inspectState(request, control), latest,
    'the exact replay cannot replace the latest durable observation');
  assert.equal(completed, false, 'old release cannot retire current loss responsibility');
  assert.equal(gateway.pending(), 1);
  assert.equal(sends, 1);
  assert.equal(cancellations, 1);
  await gateway.close();
  await cancellation;
  t.diagnostic(JSON.stringify({observations, sends, cancellations,
    finalSiteState: control.status(record), originalDispatchCid: control.identity(request)}));
});

}

for (const mode of ['transport', 'missing', 'asynchronous', 'denied']) {
  test(`Cancel retirement requires a synchronous durable receipt: ${mode}`, async t => {
    await mkdir(scratch, {recursive: true});
    const root = await mkdtemp(join(scratch, 'cancel-receipt-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const material = await certificates(root);
    const siteMaterial = {ca: material.ca, cert: material.siteCertificate,
      key: material.siteKey};
    const gateway = await startHttpsOutboundSiteGateway({
      key: material.serverKey, cert: material.serverCertificate, ca: material.ca,
      siteAuthorities: new Map([[material.siteFingerprint,
        {siteKey: 'site-a', siteGeneration: 1}]]), control,
      ...(mode === 'transport' ? {} : {receiveObservation: () =>
        mode === 'missing' ? {} : {canRetireCancellationDelivery:
          mode === 'asynchronous' ? async () => true : () => false}})});
    t.after(() => gateway.close());
    const request = dispatch({dispatchId: 'receipt-' + mode});
    let completed = false;
    const waiting = gateway.cancel({dispatch: request}).then(value => {
      completed = true; return value;
    }).catch(error => error);
    const body = JSON.stringify({version: 'actql-remote-dispatch-status/0.1',
      dispatch_request_cid: control.identity(request), revision: 1,
      state: [5, 0, 2, 0, 0], evidence: null, subject: null, measurement: null});
    assert.equal((await post(gateway.origin,
      '/v1/sites/site-a/generations/1/outbound/observations', siteMaterial, body)).status, 200);
    assert.equal(completed, mode === 'transport');
    assert.equal(gateway.pending(), mode === 'transport' ? 0 : 1);
    await gateway.close();
    await waiting;
  });
}
