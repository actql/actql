import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, open, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import type {TestContext} from 'node:test';
import type {FileHandle} from 'node:fs/promises';
import type {FixtureCleanupFailure, FixtureFailureFields, FixtureFile} from './fixtures/store-file-ports.d.mts';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';

// Actual Store, physical object, stream and OS FileHandle. Contract control
// remains the existing independent double, not original Core admission.
async function fixture(t: TestContext, {failures = 2, primary, falseClose = false, pause = false}: {failures?: number; primary?: unknown; falseClose?: boolean; pause?: boolean} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-verifier-custody-'));
  const digest = (value: string | Buffer) => `sha256:${createHash('sha256').update(value).digest('hex')}`;
  const bytes = Buffer.from('abcd');
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: digest('verifier custody authority'), capacityBytes: 1024 * 1024,
    maxObjectBytes: 4096, maxObjects: 16, maxContractNodes: 4096, maxContractDepth: 64},
  createPublicationContractControlFixture());
  const writer = store.createObjectWriter(bytes.length);
  await writer.append(bytes);
  const stored = await writer.seal(digest(bytes));
  const path = join(directory, 'objects', stored.cid.slice(7));
  const probe = await open(path, 'r');
  const prototype = Object.getPrototypeOf(probe) as Pick<FileHandle, 'stat'>, stat = prototype.stat;
  await probe.close();
  const entered = Promise.withResolvers<void>(), proceed = Promise.withResolvers<void>();
  if (!pause) proceed.resolve();
  let original: FixtureFile | undefined, nativeClose: FixtureFile['close'] | undefined, attempts = 0, stats = 0, streams = 0;
  let allowClose = false, passed = false, caught: FixtureFailureFields | undefined;
  const closeFailure = Object.assign(new Error('OriginalVerifierClosePending'), {code: 'EIO'});
  prototype.stat = (function(this: FixtureFile, ...args: Parameters<FileHandle['stat']>) {
    if (original === undefined && new Error().stack!.split('\n')[2]?.includes('verifyObject')) {
      original = this;
      nativeClose = this.close;
      const stream = this.createReadStream;
      this.createReadStream = function(this: FixtureFile, options?: Parameters<FileHandle['createReadStream']>[0]) {
        streams++;
        return Reflect.apply(stream, this, [options]);
      };
      this.close = function(this: FixtureFile, ...closeArgs: Parameters<FileHandle['close']>) {
        // FileHandle close emits the original ReadStream's native close
        // notification. It is not another product cleanup request.
        if (new Error().stack!.split('\n')[2]?.includes('node:internal/fs/streams:')) {
          return Reflect.apply(nativeClose!, this, closeArgs);
        }
        attempts++;
        if (!allowClose && attempts <= failures) {
          return falseClose ? Promise.resolve(false) : Promise.reject(closeFailure);
        }
        return Reflect.apply(nativeClose!, this, closeArgs);
      };
    }
    if (this !== original) return Reflect.apply(stat, this, args);
    stats++;
    entered.resolve();
    return proceed.promise.then(() => {
      if (primary !== undefined) throw primary;
      return Reflect.apply(stat, this, args);
    });
  }) as FileHandle['stat'];
  t.after(async () => {
    prototype.stat = stat;
    proceed.resolve();
    allowClose = true;
    if (caught?.cleanupHandle?.status().pending) await caught.cleanupHandle.retry();
    if ((original?.fd as number) >= 0) await Reflect.apply(nativeClose!, original, []);
    if (!store.status().closed) await store.close();
    if (passed) await rm(directory, {recursive: true});
    else t.diagnostic(`Preserved verifier custody failure: ${directory}`);
  });
  return {store, bytes, stored, path, closeFailure, entered, proceed,
    fd: () => original?.fd, counts: () => ({attempts, stats, streams}),
    async read() {
      try { return await store.verifyObject(stored.cid); }
      catch (error) { caught = error as FixtureFailureFields; throw error; }
    },
    pass() { passed = true; }};
}

test('Store close retains and drives the same failed verifier FD without another read', async t => {
  const f = await fixture(t);
  await assert.rejects(f.read(), error => error === f.closeFailure);
  assert((f.fd() as number) >= 0);
  const before = f.counts();
  await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
  assert.equal(f.store.status().closed, false);
  assert((f.fd() as number) >= 0);
  const one = f.store.close();
  assert.strictEqual(f.store.close(), one);
  assert.equal(await one, true);
  assert.equal(f.fd(), -1);
  assert.deepEqual(f.counts(), {...before, attempts: 3});
  assert.deepEqual(await readFile(f.path), f.bytes);
  assert.equal(await f.store.close(), true);
  assert.equal(f.counts().attempts, 3);
  f.pass();
});

test('verifier carrier retries one close flight and retires only after confirmed close', async t => {
  const f = await fixture(t);
  let failure: FixtureCleanupFailure | undefined;
  await assert.rejects(f.read(), error => { failure = error as FixtureCleanupFailure; return error === f.closeFailure; });
  const cleanup = failure!.cleanupHandle;
  assert.equal(cleanup.status().pending, true);
  const before = f.counts();
  const one = cleanup.retry();
  assert.strictEqual(cleanup.retry(), one);
  await assert.rejects(one, error => error === f.closeFailure);
  assert.equal(cleanup.status().pending, true);
  assert((f.fd() as number) >= 0);
  await cleanup.retry();
  assert.equal(cleanup.status().pending, false);
  assert.equal(f.fd(), -1);
  assert.deepEqual(f.counts(), {...before, attempts: 3});
  await cleanup.retry();
  assert.equal(f.counts().attempts, 3);
  assert.equal(await f.store.close(), true);
  f.pass();
});

for (const kind of ['mutable', 'frozen', 'readonly']) {
  test(`verifier preserves its ${kind} primary while the same FD close is pending`, async t => {
    const primary = new Error('OriginalVerifierReadFailure');
    if (kind === 'frozen') Object.freeze(primary);
    if (kind === 'readonly') Object.defineProperty(primary, 'cleanupError', {value: 'original readonly value'});
    const f = await fixture(t, {failures: 1, primary});
    let failure: FixtureCleanupFailure | undefined;
    await assert.rejects(f.read(), error => {
      failure = error as FixtureCleanupFailure;
      return kind === 'mutable' ? error === primary : (error as FixtureFailureFields).cause === primary;
    });
    assert.equal(failure!.cleanupError, f.closeFailure);
    assert.equal(failure!.cleanupHandle.status().pending, true);
    assert.equal(f.counts().streams, 0);
    if (kind === 'readonly') assert.equal((primary as FixtureFailureFields).cleanupError, 'original readonly value');
    const before = f.counts();
    assert.equal(await f.store.close(), true);
    assert.equal(f.fd(), -1);
    assert.deepEqual(f.counts(), {...before, attempts: 2});
    assert.deepEqual(await readFile(f.path), f.bytes);
    f.pass();
  });
}

test('an unsettled verification keeps its original Store alive through stat await', async t => {
  const f = await fixture(t, {failures: 0, pause: true});
  const reading = f.read();
  await f.entered.promise;
  try {
    await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
    assert.equal(f.store.status().closed, false);
    assert.equal(f.counts().attempts, 0);
    assert((f.fd() as number) >= 0);
  } finally { f.proceed.resolve(); }
  assert.deepEqual(await reading, {cid: f.stored.cid, bytes: 4});
  assert.equal(f.fd(), -1);
  assert.equal(await f.store.close(), true);
  f.pass();
});

test('false verifier close retains its same FD and Store-driven cleanup', async t => {
  const f = await fixture(t, {failures: 2, falseClose: true});
  let failure: FixtureCleanupFailure | undefined;
  await assert.rejects(f.read(), error => {
    failure = error as FixtureCleanupFailure;
    return (error as FixtureFailureFields).code === 'PublicationStoreCleanupPending';
  });
  assert.equal(failure!.cleanupHandle.status().pending, true);
  await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
  assert((f.fd() as number) >= 0);
  const before = f.counts();
  assert.equal(await f.store.close(), true);
  assert.equal(f.fd(), -1);
  assert.deepEqual(f.counts(), {...before, attempts: 3});
  assert.equal(failure!.cleanupHandle.status().pending, false);
  f.pass();
});

test('missing verifier input has no acquired FD and closed Store refuses new read IO', async t => {
  const f = await fixture(t, {failures: 0});
  await assert.rejects(f.store.verifyObject('sha256:' + '0'.repeat(64)),
    {code: 'PublicationObjectMissing'});
  assert.equal(f.fd(), undefined);
  assert.deepEqual(f.counts(), {attempts: 0, stats: 0, streams: 0});
  assert.equal(await f.store.close(), true);
  await assert.rejects(f.read(), {code: 'PublicationStoreClosed'});
  assert.equal(f.fd(), undefined);
  f.pass();
});
