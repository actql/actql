import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readdir, rmdir, writeFile, rename, unlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { createLocalRetainedStore } from './files.mjs';

const digest = text => `sha256:${createHash('sha256').update(text).digest('hex')}`;
const code = expected => error => error?.code === expected;
async function fixture(t, options = {}) {
  const parentDirectory = await mkdtemp(join(tmpdir(), 'actql-store-test-'));
  const store = await createLocalRetainedStore({ parentDirectory, capacityBytes: 100, maxFrameBytes: 16, ...options });
  t.after(async () => { store.close(); await store.cleanup(); await rmdir(parentDirectory); });
  return { store, parentDirectory };
}
async function held(store, text = '[1,2,3]') {
  const write = store.reserve(20);
  await write.start();
  await write.append(text);
  return write.seal({ bytes: Buffer.byteLength(text), cid: digest(text) });
}
async function bodyPath(parent) {
  const directory = join(parent, (await readdir(parent))[0]);
  return join(directory, (await readdir(directory))[0]);
}

test('pure settings fail before creating a store and reservations bound bytes and handles', async t => {
  const { store, parentDirectory } = await fixture(t, { maxEntries: 2 });
  const before = await readdir(parentDirectory);
  await assert.rejects(createLocalRetainedStore({ parentDirectory, capacityBytes: 100, maxFrameBytes: 0 }), code('InvalidStoreLimits'));
  assert.deepEqual(await readdir(parentDirectory), before);
  const first = store.reserve(80);
  assert.throws(() => store.reserve(21), code('StoreCapacity'));
  const second = store.reserve(0);
  assert.throws(() => store.reserve(0), code('StoreEntryLimit'));
  assert.equal(store.status().reservedBytes, 80);
  first.cancel(); second.cancel();
  await Promise.all([first.cleanupHandle.retry(), first.cleanupHandle.retry(), store.cleanup()]);
  assert.equal(store.status().reservedBytes, 0);
  assert.equal(store.status().admittedWriteBytes, 0);
  assert.equal(store.status().cleanupPending, false);
});

test('seal binds exact bytes; release preserves cumulative traffic and cannot run twice', async t => {
  const { store } = await fixture(t);
  const body = await held(store);
  assert.equal(store.status().reservedBytes, 7);
  assert.equal(store.status().holdings, 1);
  let text = '';
  assert.deepEqual(await body.consume(async chunk => { text += chunk.toString('utf8'); }), { bytes: 7, cid: digest('[1,2,3]') });
  assert.equal(text, '[1,2,3]');
  body.close(); body.close();
  assert.equal(body.available(), false);
  assert.equal(store.status().cleanupPending, true);
  await assert.rejects(body.consume(() => {}), code('RetainedUnavailable'));
  await Promise.all([body.cleanupHandle.retry(), store.cleanup(), body.cleanupHandle.retry()]);
  assert.equal(store.status().reservedBytes, 0);
  assert.equal(store.status().admittedWriteBytes, 7);
});

test('binary storage snapshots bounded bytes and seals physical identity without a logical claim', async t => {
  const {store} = await fixture(t, {maxFrameBytes: 4});
  const writer = store.reserve(6);
  await writer.start();
  for (const invalid of ['text', [1, 2], new Uint16Array(2), null]) {
    await assert.rejects(writer.appendBytes(invalid), code('InvalidStoreFrame'));
  }
  await assert.rejects(writer.appendBytes(new Uint8Array(5)), code('StoreCapacity'));
  assert.equal(store.status().admittedWriteBytes, 0);
  const source = new Uint8Array([9, 0, 255, 128, 9]);
  const pending = writer.appendBytes(source.subarray(1, 4));
  source.fill(42);
  await assert.rejects(writer.sealPhysical(), code('InvalidStoreSealState'));
  await pending;
  await writer.appendBytes(new Uint8Array([1, 2, 3]));
  await assert.rejects(writer.appendBytes(new Uint8Array([4])), code('StoreCapacity'));
  const expected = Buffer.from([0, 255, 128, 1, 2, 3]);
  const body = await writer.sealPhysical();
  assert.equal(body.bytes, expected.length);
  assert.equal(body.cid, digest(expected));
  const chunks = [];
  await body.consume(bytes => chunks.push(Buffer.from(bytes)));
  assert.deepEqual(Buffer.concat(chunks), expected);
  assert.equal(store.status().reservedBytes, 6);
  assert.equal(store.status().admittedWriteBytes, 6);
  await assert.rejects(writer.sealPhysical(), code('InvalidStoreSealState'));
  body.close(); await body.cleanupHandle.retry();
  assert.equal(store.status().reservedBytes, 0);
  assert.equal(store.status().admittedWriteBytes, 6);
});

test('batch rejection is before I/O and aggregate reservation cannot be overrun', async t => {
  const { store } = await fixture(t, { maxFrameBytes: 4 });
  const write = store.reserve(6);
  await write.start();
  await assert.rejects(write.append('12345'), code('StoreCapacity'));
  assert.equal(store.status().admittedWriteBytes, 0);
  await write.append('1234');
  await assert.rejects(write.append('567'), code('StoreCapacity'));
  assert.equal(store.status().admittedWriteBytes, 4);
  await write.append('56');
  const body = await write.seal({ bytes: 6, cid: digest('123456') });
  let reads = 0;
  await body.consume(chunk => { assert.ok(chunk.length <= 4); reads++; });
  assert.equal(reads, 2);
});

test('wrong identity leaves cleanup pending, without admitting a holding', async t => {
  const { store } = await fixture(t);
  const write = store.reserve(20);
  await write.start(); await write.append('[]');
  await assert.rejects(write.seal({ bytes: 2, cid: digest('[0]') }), error => {
    assert.equal(error.code, 'StoreIdentityMismatch');
    assert.equal(error.cleanupHandle.status().pending, true);
    return true;
  });
  assert.equal(store.status().holdings, 0);
  assert.equal(store.status().reservedBytes, 20);
  assert.equal(store.status().cleanupPending, true);
  await store.cleanup();
  assert.equal(store.status().reservedBytes, 0);
  assert.equal(store.status().admittedWriteBytes, 2);
});

test('close during a borrow revokes use but keeps capacity until the reader leaves', async t => {
  const { store } = await fixture(t);
  const body = await held(store);
  let entered;
  const inside = new Promise(resolve => { entered = resolve; });
  let resume;
  const wait = new Promise(resolve => { resume = resolve; });
  const reading = body.consume(async () => { entered(); await wait; });
  const rejected = assert.rejects(reading, code('RetainedUnavailable'));
  await inside;
  body.close();
  assert.equal(await body.cleanupHandle.retry(), false);
  assert.equal(store.status().reservedBytes, 7);
  resume(); await rejected;
  await body.cleanupHandle.retry();
  assert.equal(store.status().reservedBytes, 0);
});

test('mutation and truncation are rejected before verified consumption resolves', async t => {
  for (const [replacement, issue] of [['[9,2,3]', 'RetainedBodyChanged'], ['[', 'RetainedBodyTruncated']]) {
    const { store, parentDirectory } = await fixture(t);
    const body = await held(store);
    const path = await bodyPath(parentDirectory);
    await writeFile(path, replacement);
    await assert.rejects(body.consume(() => {}), code(issue));
    assert.equal(body.available(), false);
    assert.equal(body.cleanupHandle.status().pending, true);
    await assert.rejects(body.consume(() => {}), code('RetainedUnavailable'));
    await body.cleanupHandle.retry();
    assert.equal(store.status().reservedBytes, 0);
  }
});

test('a failed consumer callback does not revoke independent retained input', async t => {
  const { store } = await fixture(t);
  const body = await held(store);
  await assert.rejects(body.consume(() => { throw new Error('consumer failed'); }), /consumer failed/);
  assert.equal(body.available(), true);
  const result = await body.consume(() => {});
  assert.equal(result.cid, digest('[1,2,3]'));
});

test('a swapped pathname is not read or accidentally deleted during cleanup', async t => {
  const { store, parentDirectory } = await fixture(t);
  const body = await held(store);
  const path = await bodyPath(parentDirectory);
  const original = `${path}-original`;
  await rename(path, original);
  await writeFile(path, 'replacement');
  try {
    let text = '';
    await body.consume(chunk => { text += chunk.toString('utf8'); });
    assert.equal(text, '[1,2,3]');
    body.close();
    await assert.rejects(body.cleanupHandle.retry(), code('RetainedPathReplaced'));
    assert.equal(store.status().reservedBytes, 7);
    assert.equal(store.status().cleanupPending, true);
  } finally {
    await unlink(path);
    await rename(original, path);
  }
  await store.cleanup();
  assert.equal(store.status().reservedBytes, 0);
});

test('immediate and callback-wait cancellation cannot report verified consumption', async t => {
  const { store } = await fixture(t);
  const body = await held(store);
  const signal = AbortSignal.abort();
  let calls = 0;
  await assert.rejects(body.consume(() => { calls++; }, signal));
  assert.equal(calls, 0);
  const controller = new AbortController();
  await assert.rejects(body.consume(async () => { controller.abort(); }, controller.signal));
  assert.equal(body.available(), true);
  // Cancelling this read does not revoke the independently retained result.
  await body.consume(() => {});
});
