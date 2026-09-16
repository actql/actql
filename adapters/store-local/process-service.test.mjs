import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readdir, rmdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {startManagedExecution} from '../host-node/process-channel.mjs';
import {createProcessRetainedStore} from './process-service.mjs';

async function fixture(t) {
  const parentDirectory = await mkdtemp(join(tmpdir(), 'actql-control-store-service-'));
  const store = createProcessRetainedStore({parentDirectory, capacityBytes: 200, maxFrameBytes: 100, maxEntries: 2});
  const channel = await startManagedExecution({
    entry: new URL('./process-service-fixture.mjs', import.meta.url), run: 'independent-store',
    frames: {maxBytes: 4096, maxNodes: 100, maxDepth: 10},
    maxRequests: 4, maxHostCalls: 8, graceMs: 50, startupMs: 5000,
    hostService: store.service,
  });
  store.observe(channel);
  t.after(async () => {
    await channel.close(); await store.close(); await store.cleanupHandle.retry(); await rmdir(parentDirectory);
  });
  return {store, channel, parentDirectory};
}

test('selected process writes into a control-owned Store and sealed bytes survive its exit', async t => {
  const {store, channel, parentDirectory} = await fixture(t);
  assert.deepEqual(await readdir(parentDirectory), []);
  assert.equal(store.status(), undefined);
  const report = await channel.request({command: 'write', output: 'task-A'});
  const cid = `sha256:${createHash('sha256').update('[{"id":3}]').digest('hex')}`;
  assert.deepEqual({...report}, {output: 'task-A', bytes: 10, cid});
  assert.equal(channel.status().hostCalls, 2);
  await channel.close();
  const body = store.body('task-A');
  assert.equal(body.available(), true);
  assert.equal(store.status().reservedBytes, 10);
  const received = [];
  await body.consume(chunk => received.push(Buffer.from(chunk)));
  assert.equal(Buffer.concat(received).toString('utf8'), '[{"id":3}]');
  assert.equal(store.status().admittedWriteBytes, 10);
});

test('unstarted invalid Store request is correctable without creating resources', async t => {
  const {store, channel, parentDirectory} = await fixture(t);
  assert.equal((await channel.request({command: 'reserve-invalid'})).rejected, true);
  assert.equal(store.status(), undefined);
  assert.deepEqual(await readdir(parentDirectory), []);
  await channel.request({command: 'write', output: 'task-A'});
  assert.equal(store.body('task-A').available(), true);
});

test('lost writer report retains uncertain usage while prior independently sealed output remains valid', async t => {
  const {store, channel} = await fixture(t);
  await channel.request({command: 'write', output: 'task-A'});
  await assert.rejects(channel.request({command: 'crash', output: 'task-B'}),
    error => ['ExecutionExited', 'ExecutionChannelClosed'].includes(error.code));
  await channel.close();
  assert.equal(store.status().uncertainWriteBytes, 100);
  assert.equal(store.cleanupHandle.status().pending, true);
  await store.cleanupHandle.retry();
  assert.equal(store.status().reservedBytes, 10);
  assert.equal(store.body('task-A').available(), true);
  assert.equal(store.body('task-B'), undefined);
  assert.equal(store.status().admittedWriteBytes, 10);
});
