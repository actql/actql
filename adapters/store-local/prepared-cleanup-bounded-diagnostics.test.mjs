// Real Store/FD/prepared ownership; the portable contract-control is a double.
// Bounded diagnostics do not establish Resource admission or a numeric profile.
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

const cid = value => 'sha256:' + createHash('sha256').update(value).digest('hex');

async function fixture(t) {
  const directory = await fs.mkdtemp(join(tmpdir(), 'actql-prepared-bounded-errors-'));
  const bytes = Buffer.from('original finite prepared bytes\n');
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: cid('independent bounded diagnostics authority'),
    capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 8,
    maxContractNodes: 256, maxContractDepth: 32},
  createPublicationContractControlFixture());
  const originalUnlink = fs.unlink;
  let prepared, passed = false;
  t.after(async () => {
    fs.unlink = originalUnlink;
    syncBuiltinESMExports();
    try {
      if (prepared?.status().pending) await prepared.release();
      assert.equal(await store.close(), true);
      if (passed) await fs.rm(directory, {recursive: true, force: true});
      else t.diagnostic('Failed bounded-diagnostic fixture retained: ' + directory);
    } catch { t.diagnostic('Original prepared cleanup retained: ' + directory); }
  });
  const writer = store.createPreparedObjectWriter(bytes.byteLength);
  await writer.append(bytes);
  const physical = await writer.seal(cid(bytes));
  prepared = physical.prepared;
  const objectPath = join(directory, 'objects', cid(bytes).slice(7));
  return {store, bytes, prepared, objectPath,
    setFault(fault) {
      fs.unlink = async path => String(path) === objectPath ? fault() : originalUnlink(path);
      syncBuiltinESMExports();
    },
    restore() { fs.unlink = originalUnlink; syncBuiltinESMExports(); },
    passed() { passed = true; },
  };
}

test('prepared cleanup retains first/latest errors, immutable snapshots and exact original custody through retry', async t => {
  const f = await fixture(t);
  assert.equal(f.bytes.byteLength, 31);
  assert.deepEqual(f.prepared.status().errors, []);
  const cause = Object.freeze({kind: 'independent original diagnostic cause'});
  const failures = Array.from({length: 4}, (_, index) => Object.freeze(Object.assign(
    new Error('IndependentCleanupFailure' + (index + 1), {cause}), {code: 'EACCES'})));
  let calls = 0;
  f.setFault(() => { throw failures[calls++]; });
  const snapshots = [];
  for (let attempt = 0; attempt < failures.length; attempt++) {
    const first = f.prepared.release();
    assert.equal(f.prepared.release(), first, 'same in-flight cleanup, not another unlink');
    await assert.rejects(first, error => error === failures[attempt]);
    const status = f.prepared.status();
    snapshots.push(status);
    assert.equal(status.pending, true);
    assert.equal(status.errors.length, attempt === 0 ? 1 : 2);
    assert.equal(status.errors[0], failures[0]);
    assert.equal(status.errors.at(-1), failures[attempt]);
    assert.equal(status.errors[0].cause, cause);
    assert.ok(Object.isFrozen(status) && Object.isFrozen(status.errors));
    for (let old = 0; old < snapshots.length; old++) {
      assert.equal(snapshots[old].errors.length, old === 0 ? 1 : 2);
      assert.equal(snapshots[old].errors.at(-1), failures[old]);
    }
    assert.equal(f.store.status().storedBytes, 31);
    assert.equal(f.store.status().objectCount, 1);
    assert.deepEqual(await fs.readFile(f.objectPath), f.bytes);
    await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
  }
  f.restore();
  assert.equal(await f.prepared.release(), true);
  assert.equal(f.prepared.status().pending, false);
  assert.equal(f.prepared.status().errors[0], failures[0]);
  assert.equal(f.prepared.status().errors[1], failures[3]);
  assert.equal(await f.prepared.release(), false);
  assert.equal(f.store.status().storedBytes, 0);
  assert.equal(f.store.status().objectCount, 0);
  assert.equal(calls, 4);
  await assert.rejects(fs.readFile(f.objectPath), {code: 'ENOENT'});
  assert.equal(await f.store.close(), true);
  f.passed();
});

test('reusing the same error keeps both positional diagnostic roles without deduplication', async t => {
  const f = await fixture(t);
  const failure = Object.freeze(Object.assign(new Error('IndependentReusedFailure'), {code: 'EACCES'}));
  f.setFault(() => { throw failure; });
  await assert.rejects(f.prepared.release(), error => error === failure);
  const first = f.prepared.status();
  assert.equal(first.errors.length, 1);
  for (let attempt = 0; attempt < 3; attempt++) {
    await assert.rejects(f.prepared.release(), error => error === failure);
    const status = f.prepared.status();
    assert.equal(status.pending, true);
    assert.equal(status.errors.length, 2);
    assert.equal(status.errors[0], failure);
    assert.equal(status.errors[1], failure);
    assert.equal(first.errors.length, 1);
    assert.equal(f.store.status().storedBytes, 31);
  }
  f.restore();
  const completed = await f.prepared.retry();
  assert.equal(completed.pending, false);
  assert.equal(completed.errors.length, 2);
  assert.equal(completed.errors[0], failure);
  assert.equal(completed.errors[1], failure);
  assert.equal(await f.prepared.release(), false);
  assert.equal(f.store.status().storedBytes, 0);
  assert.equal(await f.store.close(), true);
  f.passed();
});
