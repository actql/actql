// Real Store/FD, existing private holding owner, Core/control double only.
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
import {preparePrivatePublicationHolding} from
  '../host-common/private-publication-holding.mjs';

const cid = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
test('existing private holding retains the original construction writer until same cleanup succeeds', async t => {
  const directory = await fs.mkdtemp(join(tmpdir(), 'actql-c-parent-writer-'));
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: cid('original parent authority'), privateEvidenceKey: Buffer.alloc(32, 7),
    capacityBytes: 1048576, maxObjectBytes: 16384, maxObjects: 40,
    maxContractNodes: 1000, maxContractDepth: 30}, createPublicationContractControlFixture());
  const originalOpen = fs.open;
  const primary = Object.freeze(Object.assign(new Error('OriginalParentWriteFailed'),
    {code: 'OriginalParentWriteFailed'}));
  let handle, owner, writes = 0, writers = 0, closes = 0, passed = false;
  fs.open = async (...args) => {
    const actual = await Reflect.apply(originalOpen, fs, args);
    if (!String(args[0]).startsWith(join(directory, 'staging', 'object-'))) return actual;
    handle = actual;
    writers++;
    return new Proxy(actual, {get(target, key) {
      if (key === 'write') return async () => { writes++; throw primary; };
      if (key === 'close') return async () => {
        if (++closes === 1) throw new Error('OriginalParentCloseFailed');
        await target.close();
      };
      const value = Reflect.get(target, key, target);
      return typeof value === 'function' ? value.bind(target) : value;
    }});
  };
  syncBuiltinESMExports();
  t.after(async () => {
    fs.open = originalOpen;
    syncBuiltinESMExports();
    try { await owner?.abort(); } catch { /* Keep same pending owner. */ }
    if (!passed && closes < 2) await handle?.close(); // Diagnostic FD only.
    try {
      assert.equal(await store.close(), true);
      if (passed) await fs.rm(directory, {recursive: true, force: true});
      else t.diagnostic(`Retained failed parent writer: ${directory}`);
    } catch { t.diagnostic(`Retained pending parent writer: ${directory}`); }
  });
  owner = preparePrivatePublicationHolding(store, {name: 'model_invocation_evidence',
    semanticCid: cid('original parent semantic'), holdingCid: cid('original parent holding'), wire: 'abc'});
  await assert.rejects(owner.commit(), error => {
    assert.equal(error.cause, primary);
    assert.equal(error.cleanupHandle, owner);
    assert.equal(error.cleanupPending, true);
    return true;
  });
  assert.equal(owner.status().preparedPending, true);
  assert.equal(owner.status().committed, false);
  assert.equal(store.status().reservedBytes, 132);
  await assert.rejects(store.close(), {code: 'PublicationStoreCleanupPending'});
  const first = owner.abort(), second = owner.abort();
  assert.equal(first, second);
  assert.equal(owner.status().operationPending, true);
  assert.equal(await first, true);
  assert.equal(owner.status().preparedPending, false);
  assert.equal(owner.status().abandoned, true);
  assert.equal(owner.status().committed, false);
  assert.deepEqual({writers, writes, closes}, {writers: 1, writes: 1, closes: 2});
  assert.equal(store.status().reservedBytes, 0);
  assert.equal(store.status().reservedObjects, 0);
  await owner.abort();
  assert.equal(closes, 2);
  passed = true;
});
