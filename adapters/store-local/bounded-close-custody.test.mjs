import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {constants} from 'node:fs';
import {lstat, mkdtemp, open, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {runInNewContext} from 'node:vm';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';

const source = await readFile(new URL('./publication-store.mjs', import.meta.url), 'utf8');
const start = source.indexOf('async function readBounded(path, maximum, closed) {');
const end = source.indexOf('\nasync function processIsAlive(', start);
assert(start >= 0 && end > start);
const body = source.slice(start, end);
const prior = JSON.parse(await readFile(new URL('./bounded-close-original.fixture.json', import.meta.url), 'utf8'));
assert.equal(createHash('sha256').update(prior.body).digest('hex'), prior.sha256);
assert.equal(prior.sha256, '161e1f00daed2495caada9977ef5aae6ebca956ed187f307dfd5040e055c0a7b');
const fail = code => { throw Object.assign(new Error(code), {code}); };

async function fixture(t, {source = body, readFailure, closeFailures = 2, openFailure} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-bounded-close-'));
  const path = join(directory, 'original');
  await writeFile(path, 'abcd');
  const original = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  let attempts = 0, opens = 0, reads = 0, released = 0, published = 0;
  let failure;
  const closeFailure = Object.assign(new Error('OriginalMetadataFdClosePending'), {code: 'EIO'});
  const read = runInNewContext(`(${source})`, {
    constants, lstat, Buffer, fail,
    quantity: value => Number.isSafeInteger(value) && value >= 0,
    async open(selected) {
      opens++;
      assert.equal(selected, path);
      if (openFailure) throw openFailure;
      return {
        stat: (...args) => original.stat(...args),
        async read(...args) { reads++; if (readFailure) throw readFailure; return original.read(...args); },
        async close() { attempts++; if (attempts <= closeFailures) throw closeFailure; await original.close(); },
      };
    },
  });
  t.after(async () => {
    attempts = closeFailures;
    if (failure?.cleanupHandle?.status().pending) await failure.cleanupHandle.retry();
    if (original.fd >= 0) await original.close();
    await rm(directory, {recursive: true});
  });
  return {path, original, closeFailure,
    counts: () => ({attempts, opens, reads, released, published}),
    async consume() {
      try {
        const bytes = await read(path, 4, () => { released++; });
        published++;
        return bytes;
      } catch (error) { failure = error; throw error; }
    },
  };
}

test('fixed old bounded reader loses failed FD cleanup custody', async t => {
  const f = await fixture(t, {source: prior.body});
  await assert.rejects(f.consume(), error => error === f.closeFailure);
  assert.equal(f.closeFailure.cleanupHandle, undefined);
  assert(f.original.fd >= 0);
  assert.deepEqual(f.counts(), {attempts: 1, opens: 1, reads: 2, released: 0, published: 0});
});

test('bounded read keeps exact failed FD and single-flight retry without a replacement read', async t => {
  const f = await fixture(t);
  await assert.rejects(f.consume(), error => error === f.closeFailure);
  const cleanup = f.closeFailure.cleanupHandle;
  assert.equal(cleanup.status().pending, true);
  assert(f.original.fd >= 0);
  const first = cleanup.retry();
  assert.strictEqual(cleanup.retry(), first);
  await assert.rejects(first, error => error === f.closeFailure);
  assert.equal(cleanup.status().pending, true);
  assert.equal(f.counts().released, 0);
  // Replacing the pathname cannot turn retry into another open/read.
  await rm(f.path);
  await writeFile(f.path, 'replacement');
  const retry = cleanup.retry();
  assert.strictEqual(cleanup.retry(), retry);
  assert.equal((await retry).pending, false);
  assert.equal(f.original.fd, -1);
  const before = f.counts();
  assert.deepEqual(before, {attempts: 3, opens: 1, reads: 2, released: 1, published: 0});
  await cleanup.retry();
  assert.deepEqual(f.counts(), before);
});

for (const frozen of [false, true]) {
  test(`bounded read retains its primary ${frozen ? 'frozen ' : ''}failure with the same FD cleanup`, async t => {
    const primary = new Error('OriginalMetadataReadFailed');
    if (frozen) Object.freeze(primary);
    const f = await fixture(t, {readFailure: primary, closeFailures: 1});
    let failure;
    await assert.rejects(f.consume(), error => {
      failure = error;
      return frozen ? error.cause === primary : error === primary;
    });
    assert.equal(failure.cleanupError, f.closeFailure);
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.equal(f.counts().released, 0);
    await failure.cleanupHandle.retry();
    assert.equal(f.original.fd, -1);
    assert.equal(f.counts().released, 1);
    assert.equal(f.counts().published, 0);
  });
}

test('bounded read confirms original close once; open refusal has no pending FD', async t => {
  const f = await fixture(t, {closeFailures: 0});
  assert.equal((await f.consume()).toString(), 'abcd');
  assert.deepEqual(f.counts(), {attempts: 1, opens: 1, reads: 2, released: 1, published: 1});
  const primary = new Error('OriginalMetadataOpenFailed');
  const rejected = await fixture(t, {openFailure: primary});
  await assert.rejects(rejected.consume(), error => error === primary);
  assert.deepEqual(rejected.counts(), {attempts: 0, opens: 1, reads: 0, released: 1, published: 0});
  assert.equal(primary.cleanupHandle, undefined);
});

test('actual original Store binding read retains Store ownership until the same metadata FD closes', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-original-binding-close-'));
  const authority = `sha256:${createHash('sha256').update('original-binding-close').digest('hex')}`;
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: authority, privateEvidenceKey: Buffer.alloc(32, 7),
    capacityBytes: 1024 * 1024, maxObjectBytes: 4096, maxObjects: 16,
    maxContractNodes: 4096, maxContractDepth: 64,
  }, createPublicationContractControlFixture());
  let prototype, stat;
  let original, attempts = 0;
  let rejectClose = true;
  const primary = Object.assign(new Error('OriginalBindingMetadataClosePending'), {code: 'EIO'});
  t.after(async () => {
    if (prototype !== undefined) prototype.stat = stat;
    rejectClose = false;
    if (primary.cleanupHandle?.status().pending) await primary.cleanupHandle.retry();
    else if (original?.fd >= 0) await original.close();
    if (!store.status().closed) await store.close();
    await rm(directory, {recursive: true});
  });
  const probe = await open(join(directory, 'store.json'), 'r');
  prototype = Object.getPrototypeOf(probe);
  stat = prototype.stat;
  await probe.close();
  prototype.stat = function(...args) {
    if (!new Error().stack.includes('at readBounded ') || original !== undefined) {
      return Reflect.apply(stat, this, args);
    }
    original = this;
    const close = this.close;
    this.close = async function() {
      attempts++;
      if (rejectClose) throw primary;
      await Reflect.apply(close, this, []);
    };
    return Reflect.apply(stat, this, args);
  };
  await assert.rejects(store.observeOriginalModelStorageBinding(), error => error === primary);
  prototype.stat = stat;
  assert(original.fd >= 0);
  assert.equal(primary.cleanupHandle.status().pending, true);
  await assert.rejects(store.close(), {code: 'PublicationStoreCleanupPending'});
  assert.equal(store.status().closed, false);
  const reader = primary.cleanupHandle;
  await assert.rejects(reader.retry(), error => error === primary);
  assert.equal(reader.status().pending, true);
  await assert.rejects(store.close(), {code: 'PublicationStoreCleanupPending'});
  assert.equal(attempts, 2);
  rejectClose = false;
  await reader.retry();
  assert.equal(original.fd, -1);
  assert.equal(reader.status().pending, false);
  await store.close();
  assert.equal(store.status().closed, true);
  const completed = attempts;
  await reader.retry();
  assert.equal(attempts, completed);
});

test('upper Evidence keeps the same Store and primary failure after a failed close', async () => {
  const source = await readFile(new URL('../host-node/local-continuation-evidence.mjs', import.meta.url), 'utf8');
  const start = source.indexOf('  function withStore(work) {');
  const end = source.indexOf('\n  async function readLedger(', start);
  assert(start >= 0 && end > start);
  let opens = 0, closes = 0, pending = true;
  const primary = Object.freeze(new Error('OriginalMetadataFailed'));
  const actualStore = {
    async recoverPhysicalHoldingDeletions() { return []; },
    async close() { closes++; if (pending) throw Object.assign(new Error('Pending'), {code: 'PublicationStoreCleanupPending'}); },
  };
  const owner = runInNewContext(`(() => { let retained; let queue=Promise.resolve(); ${source.slice(start, end)}
    return {withStore, retained: () => retained}; })()`, {
    async openStore() { opens++; return actualStore; },
  });
  await assert.rejects(owner.withStore(() => { throw primary; }), error => error === primary);
  assert.strictEqual(owner.retained(), actualStore);
  assert.equal(opens, 1);
  pending = false;
  assert.equal(await owner.withStore(store => { assert.strictEqual(store, actualStore); return 'same'; }), 'same');
  assert.equal(owner.retained(), undefined);
  assert.equal(opens, 1);
  assert.equal(closes, 2);
});
