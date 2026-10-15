// Real original Core selection and encrypted Store; synthetic physical amounts
// are not a normal profile, complete funding, Provider send or public M1 PASS.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstat, mkdir, mkdtemp, open, opendir, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {currentResourceFixture} from './model-current-resource.fixture.mjs';
import {openContinuationEvidence} from './local-continuation-evidence.mjs';

const version = 'actql-local-continuation-retention/0.1';
const unavailable = {code: 'InferOriginalMetadataAcquisitionUnavailable'};
const sha = wire => `sha256:${createHash('sha256').update(wire).digest('hex')}`;
async function fixture(t, metadata = {maxWireBytes: 1024, maxLedgerEntries: 8},
  storeBootstrap = {maxWireBytes: 4096, maxDirectoryEntries: 128}) {
  const state = await mkdtemp(join(tmpdir(), 'actql-c-original-state-save-'));
  await mkdir(join(state, 'attempts'));
  const control = runtimeCore(moon).publicationControl;
  const original = await currentResourceFixture(moon, control, 'meta', {
    storeBootstrap,
    metadataAcquisition: {metadata, directory: {maxWireBytes: 1024, maxDirectoryEntries: 8},
      retainedBytes: 7000n, workspaceBytes: 3000n},
  });
  const park = original.operation.parkOriginalResources();
  const acquisition = original.operation.originalMetadataAcquisition(park);
  const key = Buffer.alloc(32, 7);
  const keyId = sha(key);
  const ledger = {version, prepare_attempt_id: 'model-meta',
    request_cid: original.runDefinition.identity, key_id: keyId, holdings: []};
  const path = join(state, 'attempts', 'model-meta.json');
  const before = Buffer.from(JSON.stringify(ledger));
  await writeFile(path, before);
  const evidence = openContinuationEvidence({stateDirectory: state,
    key, keyId, contractControl: control,
    preparation: () => ({status: 'run_created', runStatus: 'needs_reconciliation'}),
    isTerminalRunOutcome: () => false});
  let successful = false;
  t.after(async () => {
    await evidence.close();
    assert.equal(original.sends(), 0);
    // The Core remains parked without a real journal invalidation receipt.
    // Delete only successful tests' synthetic Store/metadata after FD cleanup.
    if (successful) await rm(state, {recursive: true});
    else console.error('Preserved original state save diagnostic: ' + state);
  });
  return {...original, state, path, before, evidence, acquisition, park,
    done() { successful = true; }};
}

test('selected original state save keeps exact bytes and skips foreign metadata', async t => {
  const f = await fixture(t);
  // An ordinary opportunistic sharing scan would encounter this invalid file.
  // The exact original acquisition must not read another Run to rescue itself.
  await writeFile(join(f.state, 'attempts', 'a-foreign.json'), '['.repeat(2048));
  const wire = '{"text":"e\u0301\\r\\n","value":null}';
  const cid = await f.evidence.holdOriginalModelState('model-meta',
    f.runDefinition.identity, wire, f.acquisition);
  assert.equal(cid, sha(wire));
  const opened = await f.evidence.openOriginalModelState('model-meta', f.acquisition);
  assert.deepEqual(opened.held('original_model_state'), [cid]);
  assert.equal((await opened.bytes('original_model_state', cid)).toString('utf8'), wire);
  const saved = JSON.parse(await readFile(f.path, 'utf8'));
  assert.equal(saved.holdings.length, 1);
  assert.equal(saved.holdings[0].state, 'held');
  assert.equal(saved.holdings[0].semantic_cid, cid);
  f.done();
});

test('selected original save rejects foreign acquisition before Store and does not create a fresh ledger', async t => {
  const f = await fixture(t);
  for (const foreign of [undefined, true, {...f.acquisition}]) {
    await assert.rejects(f.evidence.holdOriginalModelState('model-meta',
      f.runDefinition.identity, 'null', foreign), unavailable);
  }
  await assert.rejects(lstat(join(f.state, 'private-store')), {code: 'ENOENT'});
  // Missing known metadata is unavailable, never an instruction to start fresh.
  await rm(f.path);
  await assert.rejects(f.evidence.holdOriginalModelState('model-meta',
    f.runDefinition.identity, 'null', f.acquisition), {code: 'ContinuationMetadataUnavailable'});
  await assert.rejects(lstat(f.path), {code: 'ENOENT'});
  f.done();
});

test('selected original save refuses entries or wire overflow without changing metadata', async t => {
  for (const bounds of [
    {maxWireBytes: 1024, maxLedgerEntries: 0, code: 'ContinuationLedgerEntriesLimit'},
    {maxWireBytes: 300, maxLedgerEntries: 8, code: 'InvalidContinuationLedger'},
  ]) {
    const f = await fixture(t, {maxWireBytes: bounds.maxWireBytes, maxLedgerEntries: bounds.maxLedgerEntries});
    await assert.rejects(f.evidence.holdOriginalModelState('model-meta',
      f.runDefinition.identity, 'null', f.acquisition), {code: bounds.code});
    assert.deepEqual(await readFile(f.path), f.before);
    f.done();
  }
});

test('selected metadata write keeps same failed FD and retries close only', async t => {
  const f = await fixture(t);
  const probe = await open(f.path, 'r');
  const prototype = Object.getPrototypeOf(probe), write = prototype.writeFile;
  await probe.close();
  let original, close, deny = true, attempts = 0, failure;
  prototype.writeFile = function(data, ...args) {
    if (original === undefined && Buffer.isBuffer(data) && data.includes(Buffer.from(version))) {
      original = this; close = this.close;
      this.close = async function() {
        assert.strictEqual(this, original); attempts++;
        if (deny) return false;
        return Reflect.apply(close, this, []);
      };
    }
    return Reflect.apply(write, this, [data, ...args]);
  };
  try {
    await assert.rejects(f.evidence.holdOriginalModelState('model-meta',
      f.runDefinition.identity, 'null', f.acquisition), error => {
      failure = error;
      return error.code === 'ContinuationWriteCleanupPending' && error.cleanupHandle.status().pending;
    });
    assert.ok(original.fd >= 0);
    assert.equal(attempts, 1);
    await assert.rejects(f.evidence.openOriginalModelState('model-meta', f.acquisition), error => error === failure);
    assert.equal(attempts, 1);
    await assert.rejects(f.evidence.close(), error => error === failure);
    assert.equal(attempts, 2);
    assert.deepEqual(await readFile(f.path), f.before);
    deny = false;
    await f.evidence.close();
    assert.equal(original.fd, -1);
    assert.equal(failure.cleanupHandle.status().pending, false);
    assert.equal(attempts, 3);
    await f.evidence.close();
    assert.equal(attempts, 3);
    assert.deepEqual(await readFile(f.path), f.before);
    f.done();
  } finally {
    prototype.writeFile = write;
    deny = false;
    if (failure?.cleanupHandle.status().pending) await failure.cleanupHandle.retry();
    else if (original?.fd >= 0) await Reflect.apply(close, original, []);
  }
});

test('selected storage binding re-observation uses original Store clamp without issuing new custody', async t => {
  const f = await fixture(t);
  // The already-issued installation binding is deliberately obtained through
  // the ordinary pre-park/bootstrap path. This test does not fund that path.
  const handle = await f.evidence.observeOriginalModelStorageBinding();
  const expected = await f.evidence.originalModelStorageBindingEvidence(handle);
  assert.strictEqual(await f.evidence.originalModelStorageBindingEvidenceSelected(handle,
    'model-meta', f.runDefinition.identity, f.acquisition), expected);
  for (const foreign of [undefined, true, {...f.acquisition}]) {
    await assert.rejects(f.evidence.originalModelStorageBindingEvidenceSelected(handle,
      'model-meta', f.runDefinition.identity, foreign), unavailable);
  }
  await assert.rejects(f.evidence.originalModelStorageBindingEvidenceSelected({...handle},
    'model-meta', f.runDefinition.identity, f.acquisition), {code: 'ForeignOriginalModelStorageBinding'});
  f.done();
  const g = await fixture(t, {maxWireBytes: 1024, maxLedgerEntries: 8},
    {maxWireBytes: 4096, maxDirectoryEntries: 0});
  const original = await g.evidence.observeOriginalModelStorageBinding();
  await assert.rejects(g.evidence.originalModelStorageBindingEvidenceSelected(original,
    'model-meta', g.runDefinition.identity, g.acquisition), {code: 'PublicationStoreBootstrapEntriesLimit'});
  // Ordinary re-observation still works but is never a selected fallback.
  assert.ok(await g.evidence.originalModelStorageBindingEvidence(original));
  g.done();
});

test('selected initial storage binding observation uses the same original acquisition and nominal binding', async t => {
  const f = await fixture(t);
  // This physical-port test uses the existing parked Core acquisition. The
  // separate caller/issuer test must establish pre-park currentness; this API
  // does not derive phase permission from a matching wire or fixture amount.
  const handle = await f.evidence.observeOriginalModelStorageBindingSelected(
    'model-meta', f.runDefinition.identity, f.acquisition);
  assert.strictEqual(await f.evidence.observeOriginalModelStorageBindingSelected(
    'model-meta', f.runDefinition.identity, f.acquisition), handle);
  const actual = await f.evidence.originalModelStorageBindingEvidenceSelected(handle,
    'model-meta', f.runDefinition.identity, f.acquisition);
  assert.equal(actual.identity, handle.identity);
  assert.equal(actual.wire, handle.wire);
  assert.equal(JSON.parse(actual.wire).key_generation_cid, sha(Buffer.alloc(32, 7)));
  assert.deepEqual(await readFile(f.path), f.before);
  f.done();
});

test('selected initial storage binding refuses foreign selection and original identities before opening', async t => {
  const f = await fixture(t);
  for (const acquisition of [undefined, true, {...f.acquisition}]) {
    await assert.rejects(f.evidence.observeOriginalModelStorageBindingSelected(
      'model-meta', f.runDefinition.identity, acquisition), unavailable);
  }
  for (const [ownerId, requestCid] of [
    ['model-foreign', f.runDefinition.identity], ['model-meta', sha('foreign')],
  ]) {
    await assert.rejects(f.evidence.observeOriginalModelStorageBindingSelected(
      ownerId, requestCid, f.acquisition), unavailable);
  }
  await assert.rejects(lstat(join(f.state, 'private-store')), {code: 'ENOENT'});
  assert.deepEqual(await readFile(f.path), f.before);
  f.done();
});

test('selected initial storage binding preserves the Store ceiling and rejects a Scope stopped during opening', async t => {
  const f = await fixture(t, {maxWireBytes: 1024, maxLedgerEntries: 8},
    {maxWireBytes: 4096, maxDirectoryEntries: 0});
  // An empty fresh Store has no acquired entries and legitimately fits zero.
  // Seed one real held object, without observing or issuing a binding yet.
  await f.evidence.hold('model-meta', f.runDefinition.identity,
    [{name: 'invocation_request', wire: 'null'}]);
  await assert.rejects(f.evidence.observeOriginalModelStorageBindingSelected(
    'model-meta', f.runDefinition.identity, f.acquisition), {code: 'PublicationStoreBootstrapEntriesLimit'});
  // Ordinary observation is only a separate control, never selected fallback.
  assert.ok(await f.evidence.observeOriginalModelStorageBinding());
  f.done();

  const g = await fixture(t), path = join(g.state, 'private-store', 'objects');
  await mkdir(path, {recursive: true});
  const probe = await opendir(path), prototype = Object.getPrototypeOf(probe);
  const read = prototype.read;
  await probe.close();
  let closing, observations = 0;
  prototype.read = function(...args) {
    if (this.path === path && observations++ === 0) {
      closing = g.operation.close().catch(error => error);
    }
    return Reflect.apply(read, this, args);
  };
  try {
    await assert.rejects(g.evidence.observeOriginalModelStorageBindingSelected(
      'model-meta', g.runDefinition.identity, g.acquisition), unavailable);
    assert.ok(observations > 0, 'the original operation changes during actual directory acquisition');
    await closing;
    await assert.rejects(lstat(join(g.state, 'private-store', 'owner')), {code: 'ENOENT'});
    assert.deepEqual(await readFile(g.path), g.before);
    g.done();
  } finally { prototype.read = read; }
});
