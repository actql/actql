import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rmdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createLocalRetainedStore, validateLocalStoreConfiguration} from './files.mjs';

async function fixture(t, options = {}) {
  const parentDirectory = await mkdtemp(join(tmpdir(), 'actql-shared-read-'));
  const store = await createLocalRetainedStore({parentDirectory, capacityBytes: 100,
    maxFrameBytes: 4, maxReadersPerBody: 2, maxReadBufferBytes: 8, ...options});
  t.after(async () => { store.close(); await store.cleanup(); await rmdir(parentDirectory); });
  const writer = store.reserve(10);
  await writer.start(); await writer.append('[1]');
  return {store, body: await writer.sealPhysical()};
}

test('separate bounded read pins survive until each consumer confirms stop', async t => {
  const {store, body} = await fixture(t);
  const a = body.delegateRead('consumer-a'), b = body.delegateRead('consumer-b');
  assert.notEqual(a.descriptor.token, b.descriptor.token);
  assert.equal(store.status().activeReaders, 2);
  assert.equal(store.status().reservedReadBufferBytes, 6);
  assert.throws(() => body.delegateRead('consumer-c'), {code: 'StoreReaderBusy'});
  const report = lease => ({version: lease.version, session: lease.session,
    token: lease.token, bytes: lease.bytes, cid: lease.cid});
  assert.throws(() => a.finish(report(b.descriptor)), {code: 'ForeignStoreReadReport'});
  assert.equal(store.status().activeReaders, 2);
  body.close();
  await store.cleanup();
  assert.equal(store.status().reservedBytes, 3);
  assert.equal(a.confirmStopped(), true); assert.equal(a.confirmStopped(), false);
  assert.equal(store.status().activeReaders, 1);
  assert.equal(store.status().reservedReadBufferBytes, 3);
  assert.throws(() => a.verify(report(a.descriptor)), {code: 'ForeignStoreReadReport'});
  await store.cleanup();
  assert.equal(store.status().reservedBytes, 3);
  b.confirmStopped(); await store.cleanup();
  assert.equal(store.status().activeReaders, 0);
  assert.equal(store.status().reservedReadBufferBytes, 0);
  assert.equal(store.status().reservedBytes, 0);
});

test('global reader-buffer admission refuses before issuing another borrow and returns capacity', async t => {
  const {store, body} = await fixture(t, {maxReadBufferBytes: 5});
  const read = body.delegateRead('a');
  assert.throws(() => body.delegateRead('b'), {code: 'StoreReadCapacity'});
  assert.equal(store.status().activeReaders, 1);
  assert.equal(store.status().reservedReadBufferBytes, 3);
  read.confirmStopped();
  const chunks = [];
  await body.consume(chunk => chunks.push(Buffer.from(chunk)));
  assert.equal(Buffer.concat(chunks).toString(), '[1]');
  assert.equal(store.status().reservedReadBufferBytes, 0);
});

test('cancelling one concurrent consumer neither frees its active buffer early nor cancels the other', {timeout: 3000}, async t => {
  const {store, body} = await fixture(t);
  const abort = new AbortController(), reason = Error('cancel-one');
  let releaseA, releaseB, enteredA, enteredB;
  const gateA = new Promise(resolve => { releaseA = resolve; });
  const gateB = new Promise(resolve => { releaseB = resolve; });
  const readyA = new Promise(resolve => { enteredA = resolve; });
  const readyB = new Promise(resolve => { enteredB = resolve; });
  const a = body.consume(async () => { enteredA(); await gateA; }, abort.signal);
  const b = body.consume(async () => { enteredB(); await gateB; });
  try {
    await Promise.all([readyA, readyB]);
    abort.abort(reason);
    assert.equal(store.status().activeReaders, 2);
    assert.equal(store.status().reservedReadBufferBytes, 6);
    releaseA();
    await assert.rejects(a, error => error === reason);
    assert.equal(store.status().activeReaders, 1);
    assert.equal(body.available(), true);
    releaseB();
    assert.equal((await b).bytes, 3);
    assert.equal(store.status().activeReaders, 0);
  } finally {
    releaseA(); releaseB(); await Promise.allSettled([a, b]);
  }
});

test('reader configuration rejects nonfinite capacities and unsafe derived arithmetic', () => {
  const base = {parentDirectory: '/unused', capacityBytes: 100, maxFrameBytes: 4};
  assert.equal(validateLocalStoreConfiguration(base).maxReadersPerBody, 1);
  for (const options of [{maxReadersPerBody: 0}, {maxReadersPerBody: 1.5},
    {maxReadBufferBytes: -1}, {maxReadBufferBytes: Infinity},
    {maxEntries: Number.MAX_SAFE_INTEGER}]) {
    assert.throws(() => validateLocalStoreConfiguration({...base, ...options}), {code: 'InvalidStoreLimits'});
  }
});
