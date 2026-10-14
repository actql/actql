import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, open, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';

// Actual Store, semantic alias, physical object and OS FileHandle. Only the
// selected original semantic FD's stat/close failures are injected. Contract
// control remains the existing independent double, not Core admission.
async function fixture(t, {closeFailures = 0, primary, pause = false, falseClose = false} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-semantic-custody-'));
  const digest = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
  const control = createPublicationContractControlFixture();
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: digest('semantic custody authority'), capacityBytes: 1024 * 1024,
    maxObjectBytes: 4096, maxObjects: 16, maxContractNodes: 4096, maxContractDepth: 64}, control);
  const contract = control.seal('run_invocation', JSON.stringify({
    version: 'actql-run-invocation/0.1', invocation_template_cid: digest('template'),
    observation_set_cid: digest('observations'),
  }), {maxWireBytes: 4096, maxNodes: 4096, maxDepth: 64});
  const stored = await store.putPublicationContract('run_invocation', contract.wire);
  const path = join(directory, 'contracts', stored.semanticCid.slice(7) + '.json');
  const originalBytes = await readFile(path);
  const probe = await open(path, 'r');
  const prototype = Object.getPrototypeOf(probe), stat = prototype.stat;
  await probe.close();
  const entered = Promise.withResolvers(), proceed = Promise.withResolvers();
  if (!pause) proceed.resolve();
  let original, nativeClose, attempts = 0, stats = 0, streams = 0;
  let allowClose = false, caught, passed = false;
  const closeFailure = Object.assign(new Error('OriginalSemanticClosePending'), {code: 'EIO'});
  prototype.stat = function(...args) {
    if (original === undefined && new Error().stack.includes('readSemanticBytes')) {
      original = this;
      nativeClose = this.close;
      const stream = this.createReadStream;
      this.createReadStream = function(options) {
        streams++;
        return Reflect.apply(stream, this, [options]);
      };
      this.close = function(...closeArgs) {
        attempts++;
        if (!allowClose && attempts <= closeFailures) {
          return falseClose ? Promise.resolve(false) : Promise.reject(closeFailure);
        }
        return Reflect.apply(nativeClose, this, closeArgs);
      };
    }
    if (this !== original) return Reflect.apply(stat, this, args);
    stats++;
    entered.resolve();
    return proceed.promise.then(() => {
      if (primary !== undefined) throw primary;
      return Reflect.apply(stat, this, args);
    });
  };
  t.after(async () => {
    prototype.stat = stat;
    proceed.resolve();
    allowClose = true;
    const cleanup = caught?.cleanupHandle;
    if (cleanup?.status().pending) await cleanup.retry();
    if (original?.fd >= 0) await Reflect.apply(nativeClose, original, []);
    if (!store.status().closed) await store.close();
    if (passed) await rm(directory, {recursive: true});
    else t.diagnostic(`Preserved semantic custody failure: ${directory}`);
  });
  return {store, contract, path, originalBytes, closeFailure, entered, proceed,
    counts: () => ({attempts, stats, streams}), fd: () => original?.fd,
    async read() {
      try { return await store.readPublicationContract(stored.semanticCid, 'run_invocation'); }
      catch (error) { caught = error; throw error; }
    },
    pass() { passed = true; }};
}

test('semantic FD close failure blocks Store release until the same close-only retry succeeds', async t => {
  const f = await fixture(t, {closeFailures: 2});
  let failure;
  await assert.rejects(f.read(), error => { failure = error; return error === f.closeFailure; });
  assert(f.fd() >= 0);
  await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
  assert.equal(f.store.status().closed, false);
  const cleanup = failure.cleanupHandle;
  assert.equal(cleanup.status().pending, true);
  const before = f.counts();
  const one = cleanup.retry();
  assert.strictEqual(cleanup.retry(), one);
  await assert.rejects(one, error => error === f.closeFailure);
  assert.equal(cleanup.status().pending, true);
  await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
  await cleanup.retry();
  assert.equal(cleanup.status().pending, false);
  assert.equal(f.fd(), -1);
  assert.deepEqual(f.counts(), {...before, attempts: 3});
  await cleanup.retry();
  assert.equal(f.counts().attempts, 3, 'confirmed physical close is not repeated');
  assert.deepEqual(await readFile(f.path), f.originalBytes);
  assert.equal(await f.store.close(), true);
  f.pass();
});

for (const frozen of [false, true]) {
  test(`semantic read failure ${frozen ? 'frozen cause' : 'primary'} survives original FD close failure`, async t => {
    const primary = new Error('OriginalSemanticReadFailure');
    if (frozen) Object.freeze(primary);
    const f = await fixture(t, {closeFailures: 1, primary});
    let failure;
    await assert.rejects(f.read(), error => {
      failure = error;
      return frozen ? error.cause === primary : error === primary;
    });
    assert.equal(failure.cleanupError, f.closeFailure);
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.equal(f.counts().streams, 0);
    await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
    await failure.cleanupHandle.retry();
    assert.equal(f.fd(), -1);
    assert.deepEqual(await readFile(f.path), f.originalBytes);
    assert.equal(await f.store.close(), true);
    f.pass();
  });
}

test('semantic read keeps the Store live during the original asynchronous FD operation', async t => {
  const f = await fixture(t, {pause: true});
  const reading = f.read();
  await f.entered.promise;
  try {
    await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
  } finally { f.proceed.resolve(); }
  const result = await reading;
  assert.equal(result.wire, f.contract.wire);
  assert.equal(f.fd(), -1);
  assert.equal(await f.store.close(), true);
  f.pass();
});

test('unacquired semantic FD leaves no reader custody and closed Store refuses new IO', async t => {
  const f = await fixture(t);
  const missing = 'sha256:' + '0'.repeat(64);
  await assert.rejects(f.store.readSemanticBytes(missing), {code: 'PublicationContractMissing'});
  assert.equal(f.fd(), undefined);
  assert.equal(await f.store.close(), true);
  await assert.rejects(f.read(), {code: 'PublicationStoreClosed'});
  assert.equal(f.fd(), undefined);
  f.pass();
});

test('false semantic close retains the original FD and Store custody', async t => {
  const f = await fixture(t, {closeFailures: 1, falseClose: true});
  let failure;
  await assert.rejects(f.read(), error => {
    failure = error;
    return error.code === 'PublicationSemanticReaderCleanupPending';
  });
  assert(f.fd() >= 0);
  await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
  await failure.cleanupHandle.retry();
  assert.equal(f.fd(), -1);
  assert.equal(await f.store.close(), true);
  f.pass();
});
