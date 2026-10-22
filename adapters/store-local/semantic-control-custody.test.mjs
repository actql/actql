import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {EventEmitter} from 'node:events';
import {mkdtemp, open, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {Readable} from 'node:stream';
import {inspect} from 'node:util';
import test from 'node:test';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {installResultAccessAuthority, installResultAccessService} from '../host-common/result-access.mjs';
import {createNodeInProcessClientHost} from '../host-node/in-process-client.mjs';
import {createClientHttpHandler} from '../host-node/client-http.mjs';
import {createInstalledHostShutdown} from '../host-node/installed-host-cleanup.mjs';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId: 'namespace-a', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'volatile', scopeRef: 'local-principal', capabilities: [], limits: {
    maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}};
const request = {connection: {mode: 'local', owner: 'local', consentRefs: [], runners: []}, ref, resultName: 'answer',
  format: 'jsonl', attemptId: 'metadata', maxWireBytes: 4096, maxNodes: 1000, maxDepth: 32};

// Actual Store and OS FileHandles, existing public SDK/ingress and shutdown.
// Contract/Result controls and the committed-index lookup are independent
// doubles: the first real semantic read fails before any projected Result.
async function fixture(t, {failures = 1, primary, holdClose = false} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-semantic-control-custody-'));
  const digest = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
  const contractControl = createPublicationContractControlFixture();
  const store = await openLocalPublicationStore({directory, storeAuthorityCid: digest('control authority'),
    capacityBytes: 1024 * 1024, maxObjectBytes: 4096, maxObjects: 16,
    maxContractNodes: 4096, maxContractDepth: 64}, contractControl);
  const contract = contractControl.seal('run_invocation', JSON.stringify({
    version: 'actql-run-invocation/0.1', invocation_template_cid: digest('template'),
    observation_set_cid: digest('observations')}), {maxWireBytes: 4096, maxNodes: 4096, maxDepth: 64});
  const stored = await store.putPublicationContract('run_invocation', contract.wire);
  const path = join(directory, 'contracts', stored.semanticCid.slice(7) + '.json');
  const originalBytes = await readFile(path);
  const probe = await open(path, 'r'), prototype = Object.getPrototypeOf(probe), stat = prototype.stat;
  await probe.close();
  const records = [], native = new Map(), closeEntered = Promise.withResolvers(), proceed = Promise.withResolvers();
  if (!holdClose) proceed.resolve();
  let passed = false, allowClose = false, reads = 0, failureFacts;
  const secret = 'private-semantic-close-secret';
  const closeFailure = Object.assign(new Error(secret), {code: 'EIO'});
  prototype.stat = function (...args) {
    let record = native.get(this);
    if (record === undefined && new Error().stack.split('\n')[2]?.includes('at readSemanticBytes')) {
      record = {handle: this, close: this.close, attempts: 0, stats: 0, streams: 0};
      records.push(record); native.set(this, record);
      const stream = this.createReadStream;
      this.createReadStream = options => { record.streams++; return Reflect.apply(stream, this, [options]); };
      this.close = (...closeArgs) => {
        if (new Error().stack.split('\n')[2]?.includes('node:internal/fs/streams:')) {
          return Reflect.apply(record.close, this, closeArgs);
        }
        record.attempts++;
        if (!allowClose && record.attempts <= failures) return Promise.reject(closeFailure);
        closeEntered.resolve();
        return proceed.promise.then(() => Reflect.apply(record.close, this, closeArgs));
      };
    }
    if (record === undefined) return Reflect.apply(stat, this, args);
    record.stats++;
    if (primary !== undefined) return Promise.reject(primary);
    return Reflect.apply(stat, this, args);
  };
  const control = Object.fromEntries(['issueResultReadGrant', 'resultReadAvailability',
    'resultReadExtendedAvailability', 'resultReadGrantValidAt', 'beginResultAccessProgress',
    'resultAccessProgressAction', 'recordResultAccessRequestAuthorization', 'recordResultAccessResolution',
    'recordResultAccessInitialAvailability', 'recordResultAccessReadAdmission', 'recordResultAccessGrant',
    'resultReadDefinitionCid', 'resultReadRetentionPolicyCid', 'resultRetentionClockContractCid',
    'describeCommittedResult', 'resultMetadataRetentionState', 'issueManifestReadGrant',
    'manifestReadGrantAllowsBytes', 'manifestReadGrantValidAt'].map(name => [name, () => {}]));
  // This fixture fails at its first physical metadata read, before any
  // Result clock/grant observation. Keep the real service shape without
  // replacing the Store's durable clock or manufacturing an observation.
  control.trustedClockNotBefore = () => assert.fail('Clock reached before failed metadata read');
  const serviceStore = {...store,
    async confirmCommittedIndex() { return {public_index_entry_cid: cid('2'), result_manifest_cid: cid('3')}; },
    async readPublicationContract() {
      reads++;
      try { return await store.readPublicationContract(stored.semanticCid, 'run_invocation'); }
      catch (error) {
        // Observe booleans only; never retain an Error to rescue the caller.
        failureFacts = {wrapped: error !== primary, originalCause: error.cause === primary,
          hasCleanup: typeof error.cleanupHandle?.retry === 'function'};
        throw error;
      }
    }};
  const authority = installResultAccessAuthority({authorizeResultReadRequest() {}, admitResultRead() {},
    authorizeResultRead() {}, authorizeResultDescription: () => true, admitResultDescription() {}});
  const resultService = installResultAccessService({store: serviceStore, control, authority,
    now: () => '2026-10-15T00:00:00.000Z', createDigest() {},
    limits: {maxWireBytes: 4096, maxNodes: 1000, maxDepth: 32},
    frameLimits: {maxRowBytes: 1024, maxDepth: 32, maxFrameBytes: 4096}});
  const operations = {authenticate: () => 'local-principal', authorizeConnection: () => true,
    negotiate: () => profile, attach: () => ({ref, durability: 'volatile', revision: 1}),
    resultService, maxRowBytes: 1024};
  const ingress = createNodeInProcessClientHost(operations);
  const shutdown = createInstalledHostShutdown({stop() {}, drain() {}, retire() {}, checkpoint() {},
    journal() {}, source() {}, effect() {}, store: () => store.close()});
  const client = await connectInProcess({mode: 'local', owner: 'local'},
    {perform: ingress.perform, close: () => shutdown.close()});
  t.after(async () => {
    prototype.stat = stat; proceed.resolve(); allowClose = true;
    // Failure fixtures preserve bytes; physical safety teardown uses the same
    // Store. No test-only read Error is retained to rescue the public caller.
    try { await client.close(); } catch {}
    for (const record of records) if (record.handle.fd >= 0) await Reflect.apply(record.close, record.handle, []);
    if (passed) await rm(directory, {recursive: true});
    else t.diagnostic(`Preserved control-read custody failure: ${directory}`);
  });
  return {store, client, ingress, operations, records, shutdown, closeEntered, proceed, path, originalBytes,
    reads: () => reads, failureFacts: () => failureFacts, secret, pass() { passed = true; }};
}

async function refused(f) {
  const run = await f.client.attach(ref);
  await assert.rejects(run.result('answer').describe(), error => {
    assert.equal(error.code, 'ClientHostFailure');
    assert.equal(error.cause, undefined); assert.equal(error.cleanupHandle, undefined);
    assert.doesNotMatch(inspect(error, {showHidden: true, depth: 8}), /private-semantic-/u);
    return true;
  });
}

test('redacted control-read failure remains on the same Store and Client.close drains only its original FD', async t => {
  const f = await fixture(t, {holdClose: true});
  await refused(f);
  const before = f.records.map(r => ({stats: r.stats, streams: r.streams}));
  const one = f.client.close(), two = f.client.close();
  assert.strictEqual(one, two);
  await f.closeEntered.promise;
  assert.equal(f.store.status().closed, false);
  await assert.rejects(f.store.readSemanticBytes(cid('9')), {code: 'PublicationStoreClosed'});
  f.proceed.resolve();
  await one;
  assert.equal(f.records.length, 1); assert.equal(f.records[0].handle.fd, -1);
  assert.equal(f.records[0].attempts, 2);
  assert.deepEqual(f.records.map(r => ({stats: r.stats, streams: r.streams})), before);
  assert.equal(f.reads(), 1); assert.equal(f.store.status().closed, true);
  await f.client.close(); assert.equal(f.records[0].attempts, 2);
  assert.deepEqual(await readFile(f.path), f.originalBytes);
  f.pass();
});

test('failed shutdown retains the private semantic FD for single-flight close-only retry', async t => {
  const f = await fixture(t, {failures: 2});
  await refused(f);
  await assert.rejects(f.client.close(), {code: 'ClientCleanupPending'});
  assert.equal(f.store.status().closed, false); assert(f.records[0].handle.fd >= 0);
  const first = f.client.close(); assert.strictEqual(first, f.client.close());
  await first; assert.equal(f.records[0].attempts, 3);
  assert.equal(f.records[0].handle.fd, -1); assert.equal(f.reads(), 1);
  f.pass();
});

test('frozen control-read primary stays private through Host cleanup', async t => {
  const f = await fixture(t, {primary: Object.freeze(new Error('private-semantic-primary-secret'))});
  await refused(f);
  assert.equal(f.records[0].streams, 0);
  await f.client.close(); assert.equal(f.records[0].handle.fd, -1);
  assert.equal(f.records[0].attempts, 2); assert.equal(f.reads(), 1);
  f.pass();
});

test('two redacted control reads retain their own original FDs in the same Store lifetime', async t => {
  const f = await fixture(t);
  await refused(f); await refused(f);
  assert.equal(f.records.length, 2);
  await f.client.close();
  assert.deepEqual(f.records.map(r => [r.handle.fd, r.attempts]), [[-1, 2], [-1, 2]]);
  assert.equal(f.reads(), 2);
  f.pass();
});

test('HTTP code redaction leaves the original semantic close duty on the same Store shutdown', async t => {
  const f = await fixture(t);
  let status, body;
  const requestStream = Readable.from([Buffer.from(JSON.stringify(request))]);
  Object.assign(requestStream, {method: 'POST', url: '/actql/client/0.1/result-describe',
    headers: {'content-type': 'application/json'}});
  const response = Object.assign(new EventEmitter(), {headersSent: false,
    writeHead(code) {status = code;}, end(value) {body = value;}});
  await createClientHttpHandler(f.operations)(requestStream, response);
  assert.equal(status, 500); assert.deepEqual(JSON.parse(body), {code: 'ClientHostFailure'});
  assert.doesNotMatch(body, new RegExp(f.secret));
  await f.shutdown.close();
  assert.equal(f.records[0].handle.fd, -1); assert.equal(f.records[0].attempts, 2);
  assert.equal(f.reads(), 1); f.pass();
});

// No Proxy/plugin defense: an ordinary extensible Error has one pre-existing
// readonly field. Its private duty must be owned before outward decoration.
test('readonly primary cleanup property cannot orphan the original control-read FD', async t => {
  const primary = new Error('private-semantic-primary-secret');
  const original = new Error('private-semantic-original-cleanup-secret');
  Object.defineProperty(primary, 'cleanupError', {value: original, writable: false});
  const keys = Reflect.ownKeys(primary);
  const f = await fixture(t, {primary});
  await refused(f);
  assert.equal(primary.cleanupError, original);
  assert.deepEqual(Reflect.ownKeys(primary), keys);
  assert.deepEqual(f.failureFacts(), {wrapped: true, originalCause: true, hasCleanup: true});
  await f.client.close();
  assert.equal(f.records[0].handle.fd, -1); assert.equal(f.records[0].attempts, 2);
  assert.equal(f.reads(), 1); assert.equal(f.store.status().closed, true);
  f.pass();
});
