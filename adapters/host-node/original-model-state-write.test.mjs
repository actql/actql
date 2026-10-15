// Real original Core selection and encrypted Store; synthetic physical amounts
// are not a normal profile, complete funding, Provider send or public M1 PASS.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstat, mkdir, mkdtemp, open, readFile, rm, writeFile} from 'node:fs/promises';
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
async function fixture(t, metadata = {maxWireBytes: 1024, maxLedgerEntries: 8}) {
  const state = await mkdtemp(join(tmpdir(), 'actql-c-original-state-save-'));
  await mkdir(join(state, 'attempts'));
  const control = runtimeCore(moon).publicationControl;
  const original = await currentResourceFixture(moon, control, 'meta', {
    storeBootstrap: {maxWireBytes: 4096, maxDirectoryEntries: 128},
    metadataAcquisition: {metadata, directory: {maxWireBytes: 1024, maxDirectoryEntries: 8},
      retainedBytes: 7000n, workspaceBytes: 3000n},
  });
  const park = original.operation.parkOriginalResources();
  const acquisition = original.operation.originalMetadataAcquisition(park);
  const keyId = `sha256:${'2'.repeat(64)}`;
  const ledger = {version, prepare_attempt_id: 'model-meta',
    request_cid: original.runDefinition.identity, key_id: keyId, holdings: []};
  const path = join(state, 'attempts', 'model-meta.json');
  const before = Buffer.from(JSON.stringify(ledger));
  await writeFile(path, before);
  const evidence = openContinuationEvidence({stateDirectory: state,
    key: Buffer.alloc(32, 7), keyId, contractControl: control,
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
