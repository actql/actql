import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rmdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { createLocalRetainedStore } from './files.mjs';
import { openDelegatedFile } from './delegated-file.mjs';
import { consumeDelegatedFile } from './delegated-reader.mjs';
import { startManagedExecution } from '../host-node/process-channel.mjs';

async function fixture(t) {
  const parentDirectory = await mkdtemp(join(tmpdir(), 'actql-delegated-test-'));
  const store = await createLocalRetainedStore({ parentDirectory, capacityBytes: 100, maxFrameBytes: 4 });
  t.after(async () => { store.close(); await store.cleanup(); await rmdir(parentDirectory); });
  const write = store.reserve(20);
  await write.start();
  return { store, write };
}

test('control-owned inode survives writer process exit without body transfer', async t => {
  const { store, write } = await fixture(t);
  const process = await startManagedExecution({
    entry: new URL('./delegated-file-fixture.mjs', import.meta.url), run: 'owned-run',
    frames: { maxBytes: 4096, maxNodes: 100, maxDepth: 10 },
    maxRequests: 2, graceMs: 100, startupMs: 5000,
  });
  t.after(() => process.close());
  const lease = write.delegate(process.identity().session);
  const report = await process.request({ command: 'write', lease });
  assert.deepEqual(Object.keys(report).sort(), ['bytes', 'cid', 'session', 'token', 'version']);
  const body = await write.finishDelegated(report);
  await assert.rejects(process.request({ command: 'exit' }), error =>
    ['ExecutionExited', 'ExecutionChannelClosed'].includes(error.code));
  assert.equal((await process.close()).code, 7);
  assert.equal(process.status().exited, true);
  assert.equal(body.available(), true);
  const reader = await startManagedExecution({
    entry: new URL('./delegated-file-fixture.mjs', import.meta.url), run: 'owned-run',
    frames: { maxBytes: 4096, maxNodes: 100, maxDepth: 10 },
    maxRequests: 1, graceMs: 100, startupMs: 5000,
  });
  t.after(() => reader.close());
  assert.notEqual(reader.identity().session, process.identity().session);
  const borrow = body.delegateRead(reader.identity().session);
  try {
    const readReport = await reader.request({ command: 'read', lease: borrow.descriptor });
    assert.deepEqual(Object.keys(readReport).sort(), ['bytes', 'cid', 'session', 'token', 'version']);
    assert.equal(borrow.finish(readReport).cid, body.cid);
  } finally {
    await reader.close();
    borrow.confirmStopped();
  }
  assert.equal(body.cid, `sha256:${createHash('sha256').update('[0,1]').digest('hex')}`);
  assert.equal(store.status().reservedBytes, 5);
  assert.equal(store.status().admittedWriteBytes, 5);
  assert.equal(store.status().delegatedWriteBytes, 0);
  assert.equal(store.status().uncertainWriteBytes, 0);
  await assert.rejects(write.finishDelegated(report), { code: 'ForeignStoreReport' });
  body.close(); await body.cleanupHandle.retry();
  assert.equal(store.status().reservedBytes, 0);
  assert.equal(store.status().admittedWriteBytes, 5);
});

test('cancellation preserves reservation until confirmed writer stop and preserves unknown traffic', async t => {
  const { store, write } = await fixture(t);
  const lease = write.delegate('session');
  const writer = await openDelegatedFile(lease);
  await writer.append('[0]');
  write.cancel();
  assert.equal(await write.cleanupHandle.retry(), false);
  assert.equal(store.status().reservedBytes, 20);
  assert.equal(store.status().delegatedWriteBytes, 20);
  await writer.close();
  assert.equal(write.confirmDelegatedStopped(), true);
  assert.equal(write.confirmDelegatedStopped(), false);
  await write.cleanupHandle.retry();
  assert.equal(store.status().reservedBytes, 0);
  assert.equal(store.status().uncertainWriteBytes, 20);
  assert.equal(store.status().delegatedWriteBytes, 0);
});

test('exact writer binding rejects foreign reports without releasing active writer', async t => {
  const { store, write } = await fixture(t);
  const lease = write.delegate('session');
  const writer = await openDelegatedFile(lease);
  await writer.append('[]');
  const report = await writer.seal();
  for (const change of [{ token: 'foreign' }, { session: 'other' }, { bytes: 21 }]) {
    await assert.rejects(write.finishDelegated({ ...report, ...change }), { code: 'ForeignStoreReport' });
    assert.equal(store.status().reservedBytes, 20);
    assert.equal(store.status().delegatedWriteBytes, 20);
  }
  const body = await write.finishDelegated(report);
  assert.equal(body.available(), true);
});

test('writer validates exact inode and bounded frames before accepting bytes', async t => {
  const { write } = await fixture(t);
  const lease = write.delegate('session');
  await assert.rejects(openDelegatedFile({ ...lease, inode: lease.inode + 1 }), { code: 'ForeignStoreFile' });
  const writer = await openDelegatedFile(lease);
  await assert.rejects(writer.append('12345'), { code: 'StoreCapacity' });
  await writer.append('[]');
  const report = await writer.seal();
  assert.equal(report.bytes, 2);
  await write.finishDelegated(report);
});

test('writer crash without terminal receipt retains capacity until actual exit is confirmed', async t => {
  const { store, write } = await fixture(t);
  const process = await startManagedExecution({
    entry: new URL('./delegated-file-fixture.mjs', import.meta.url), run: 'failed-run',
    frames: { maxBytes: 4096, maxNodes: 100, maxDepth: 10 },
    maxRequests: 1, graceMs: 100, startupMs: 5000,
  });
  t.after(async () => {
    await process.close();
    write.confirmDelegatedStopped();
    await write.cleanupHandle.retry();
  });
  const lease = write.delegate(process.identity().session);
  await assert.rejects(process.request({ command: 'crash-writing', lease }), error =>
    ['ExecutionExited', 'ExecutionChannelClosed'].includes(error.code));
  write.cancel();
  assert.equal(await write.cleanupHandle.retry(), false);
  assert.equal(store.status().reservedBytes, 20);
  assert.equal(store.status().holdings, 0);
  assert.equal((await process.close()).code, 9);
  write.confirmDelegatedStopped();
  await write.cleanupHandle.retry();
  assert.equal(store.status().reservedBytes, 0);
  assert.equal(store.status().uncertainWriteBytes, 20);
});

test('delegated borrow retains a closed body until reader stop, without publishing success', async t => {
  const { store, write } = await fixture(t);
  await write.append('[0]');
  const body = await write.seal({ bytes: 3, cid: `sha256:${createHash('sha256').update('[0]').digest('hex')}` });
  const borrow = body.delegateRead('reader');
  let entered, resume;
  const inside = new Promise(resolve => { entered = resolve; });
  const gate = new Promise(resolve => { resume = resolve; });
  const reading = consumeDelegatedFile(borrow.descriptor, async () => { entered(); await gate; });
  await inside;
  body.close();
  assert.equal(await body.cleanupHandle.retry(), false);
  assert.equal(store.status().reservedBytes, 3);
  resume();
  const report = await reading;
  assert.throws(() => borrow.finish({ ...report, session: 'other' }), { code: 'ForeignStoreReadReport' });
  assert.equal(await body.cleanupHandle.retry(), false);
  assert.throws(() => borrow.finish(report), { code: 'RetainedUnavailable' });
  assert.equal(borrow.confirmStopped(), false);
  await body.cleanupHandle.retry();
  assert.equal(store.status().reservedBytes, 0);
});

test('delegated read rejects changed bytes and preserves independent body after consumer failure', async t => {
  const { write } = await fixture(t);
  await write.append('[0]');
  const body = await write.seal({ bytes: 3, cid: `sha256:${createHash('sha256').update('[0]').digest('hex')}` });
  const first = body.delegateRead('reader');
  await assert.rejects(consumeDelegatedFile(first.descriptor, () => { throw Error('consumer failed'); }), /consumer failed/);
  first.confirmStopped();
  assert.equal(body.available(), true);
  const second = body.delegateRead('reader-2');
  await writeFile(second.descriptor.path, '[9]');
  await assert.rejects(consumeDelegatedFile(second.descriptor, () => {}), { code: 'RetainedBodyChanged' });
  second.confirmStopped();
  body.close();
});
