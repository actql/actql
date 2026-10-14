// Real FD/Store witness with explicit Core contract-control double. A write
// failure plus close failure must retain the original writer's retry duty;
// neither this witness nor disk accounting supplies a Model capacity grant.
import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';

const cid = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;

for (const bytesEntry of [false, true]) for (const frozen of [false, true]) {
test(`private ${bytesEntry ? 'raw bytes' : 'wire'} writer retains ${frozen ? 'frozen' : 'mutable'} failure and same FD cleanup`, async t => {
  const directory = await fs.mkdtemp(join(tmpdir(), 'actql-c-private-writer-'));
  const configuration = {directory, storeAuthorityCid: cid('original writer authority'),
    privateEvidenceKey: Buffer.alloc(32, 7), capacityBytes: 1048576,
    maxObjectBytes: 16384, maxObjects: 40, maxContractNodes: 1000, maxContractDepth: 30};
  const store = await openLocalPublicationStore(configuration,
    createPublicationContractControlFixture());
  const originalOpen = fs.open;
  const primary = Object.assign(new Error('OriginalPrivateWriteFailed'),
    {code: 'OriginalPrivateWriteFailed'});
  if (frozen) Object.freeze(primary);
  const closeFailure = new Error('OriginalPrivateCloseFailed');
  const state = {writers: 0, writes: 0, closeAttempts: 0, physicalCloses: 0};
  let originalHandle, error, passed = false;
  fs.open = async (...args) => {
    const handle = await Reflect.apply(originalOpen, fs, args);
    if (!String(args[0]).startsWith(join(directory, 'staging', 'object-'))) return handle;
    state.writers++;
    assert.equal(state.writers, 1);
    originalHandle = handle;
    return new Proxy(handle, {get(target, key) {
      if (key === 'write') return async () => { state.writes++; throw primary; };
      if (key === 'close') return async () => {
        if (++state.closeAttempts === 1) throw closeFailure;
        await target.close();
        state.physicalCloses++;
      };
      const value = Reflect.get(target, key, target);
      return typeof value === 'function' ? value.bind(target) : value;
    }});
  };
  syncBuiltinESMExports();
  t.after(async () => {
    fs.open = originalOpen;
    syncBuiltinESMExports();
    // On a failing baseline there is no exported writer cleanup capability.
    // Close only this diagnostic's exact FD, preserve the pending Store/root
    // and original key/metadata. Do not pretend its capacity was settled.
    if (error?.cleanupHandle !== undefined) {
      try { await error.cleanupHandle.release(); } catch { /* Retain below. */ }
    }
    if (!passed && originalHandle !== undefined && state.physicalCloses === 0) {
      await originalHandle.close();
      t.diagnostic('Diagnostic FD close only; missing product cleanup responsibility is not settled.');
    }
    try {
      assert.equal(await store.close(), true);
      if (passed) await fs.rm(directory, {recursive: true, force: true});
      else t.diagnostic(`Retained failed writer fixture: ${directory}`);
    } catch {
      t.diagnostic(`Retained pending writer fixture: ${directory}; ${JSON.stringify(store.status())}`);
    }
  });
  const bytes = Buffer.from('abc');
  const binding = {semanticCid: cid('original raw descriptor'),
    holdingCid: cid('original raw holding'), wire: '', byteCount: bytes.length,
    contentCid: cid(bytes)};
  try {
    if (bytesEntry) await store.prepareModelRawEvidence(binding, bytes);
    else await store.preparePrivateEvidence('model_invocation_evidence', 'abc', binding.semanticCid);
    assert.fail('Original write must fail');
  } catch (observed) { error = observed; }
  // E(3)=132 independently fixed closed-envelope bytes, never a heap amount.
  assert.equal(store.status().reservedBytes, 132);
  assert.equal(store.status().reservedObjects, 1);
  assert.deepEqual(state, {writers: 1, writes: 1, closeAttempts: 1, physicalCloses: 0});
  assert.equal(frozen ? error.cause : error, primary);
  assert.equal(error.cleanupFailure, closeFailure);
  assert.equal(error.cleanupPending, true);
  const cleanup = error.cleanupHandle;
  assert.equal(typeof cleanup?.release, 'function');
  assert.equal(cleanup.status().pending, true);
  await assert.rejects(store.close(), {code: 'PublicationStoreCleanupPending'});
  const first = cleanup.release(), second = cleanup.release();
  assert.equal(first, second, 'same original cleanup single flight');
  assert.equal(cleanup.status().pending, true);
  assert.equal(await first, true);
  assert.equal(cleanup.status().pending, false);
  assert.equal(await cleanup.release(), false);
  assert.equal((await cleanup.retry()).pending, false);
  assert.deepEqual(state, {writers: 1, writes: 1, closeAttempts: 2, physicalCloses: 1});
  assert.equal(store.status().reservedBytes, 0);
  assert.equal(store.status().reservedObjects, 0);
  assert.equal(store.status().storedBytes, 0);
  passed = true;
});
}
