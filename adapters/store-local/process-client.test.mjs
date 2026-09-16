import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rmdir, readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {bindProcessStore} from './process-binding.mjs';
import {createProcessStoreLease, processRetainedBodyIdentity} from './process-client.mjs';
import {createProcessRetainedStore} from './process-service.mjs';
import {registerRetainedInput, retainedStorageBody} from './representations.mjs';

test('process Store seals binary physical identity without relaying payload or granting completion', async () => {
  for (const mode of ['physical', 'expected', 'mismatch', 'cancel']) {
    const parentDirectory = await mkdtemp(join(tmpdir(), 'actql-binary-lease-'));
    const store = createProcessRetainedStore({parentDirectory, capacityBytes: 8, maxFrameBytes: 4, maxEntries: 1});
    const identity = {session: 'binary-session', run: 'same-run'};
    let stop;
    const stopped = new Promise(resolve => { stop = resolve; });
    store.observe({identity: () => identity, cleanupHandle: {whenStopped: () => stopped}});
    const controller = new AbortController(), messages = [];
    const context = {...identity, callHost: request => {
      messages.push(structuredClone(request));
      return store.service.invoke(request, controller.signal,
        {...identity, sequence: 1, call: messages.length});
    }};
    const binding = bindProcessStore(context);
    const lease = createProcessStoreLease(binding, 'output', 8, 4, controller.signal);
    try {
      const writer = lease.reserve(8);
      await writer.start();
      await assert.rejects(writer.appendBytes(new Uint8Array(5)), {code: 'StoreCapacity'});
      const source = new Uint8Array([0, 255, 128, 1]);
      const pending = writer.appendBytes(source);
      source.fill(42);
      await pending;
      const expected = Buffer.from([0, 255, 128, 1]);
      const cid = `sha256:${createHash('sha256').update(expected).digest('hex')}`;
      assert.deepEqual(messages.map(value => value.command), ['reserve']);
      assert.equal(store.body('output'), undefined);
      if (mode === 'cancel') {
        controller.abort();
        await assert.rejects(writer.sealPhysical());
        assert.equal(store.body('output'), undefined);
      } else if (mode === 'mismatch') {
        await assert.rejects(writer.seal({bytes: 4, cid: `sha256:${'0'.repeat(64)}`}), {code: 'StoreIdentityMismatch'});
        assert.equal(store.body('output'), undefined);
      } else {
        const body = mode === 'physical' ? await writer.sealPhysical() : await writer.seal({bytes: 4, cid});
        assert.equal(body.bytes, 4);
        assert.equal(body.cid, cid);
        assert.deepEqual(processRetainedBodyIdentity(body, binding), {...identity, output: 'output', bytes: 4, cid});
        assert.equal(store.body('output').cid, cid);
        assert.equal(store.status().reservedBytes, 4);
        assert.deepEqual(messages.map(value => value.command), ['reserve', 'seal']);
        assert.deepEqual(Object.keys(messages[1]).sort(), ['command', 'output', 'report']);
        assert.deepEqual(Object.keys(messages[1].report).sort(), ['bytes', 'cid', 'session', 'token', 'version']);
        const chunks = [];
        await body.consume(chunk => chunks.push(Buffer.from(chunk)));
        assert.deepEqual(Buffer.concat(chunks), expected);
        await assert.rejects(writer.sealPhysical(), {code: 'InvalidStoreWriteState'});
      }
    } finally {
      lease.close(); await lease.cleanup(); stop(); await stopped;
      await store.close(); await store.cleanupHandle.retry(); await rmdir(parentDirectory);
    }
  }
});

test('completion storage lookup keeps exact material, lease and process binding with real sealed bytes', async () => {
  const parentDirectory = await mkdtemp(join(tmpdir(), 'actql-completion-lease-'));
  const store = createProcessRetainedStore({parentDirectory, capacityBytes: 100, maxFrameBytes: 100, maxEntries: 1});
  const identity = {session: 'installed-session', run: 'same-run'};
  let stop;
  const stopped = new Promise(resolve => { stop = resolve; });
  store.observe({identity: () => identity, cleanupHandle: {whenStopped: () => stopped}});
  const controller = new AbortController();
  let calls = 0;
  const context = {...identity, callHost: request => store.service.invoke(request,
    controller.signal, {...identity, sequence: 1, call: ++calls})};
  const binding = bindProcessStore(context);
  const lease = createProcessStoreLease(binding, 'task-1', 100, 100, controller.signal);
  try {
    const writer = lease.reserve(100);
    await writer.start();
    await writer.append('[]');
    const cid = `sha256:${createHash('sha256').update('[]').digest('hex')}`;
    const body = await writer.seal({bytes: 2, cid});
    const material = {}, input = {};
    registerRetainedInput(material, read => read === input, body,
      {maxFrameBytes: 100, wire: {max_bytes: 100}});
    assert.equal(retainedStorageBody(material), body);
    assert.throws(() => retainedStorageBody({...material}), /ForeignRetainedStorage/);
    assert.deepEqual(processRetainedBodyIdentity(body, binding), {...identity, output: 'task-1', bytes: 2, cid});
    assert.throws(() => processRetainedBodyIdentity({...body}, binding), {code: 'ForeignRetainedStoreBody'});
    // Even a second installed binding with equal session strings is not the
    // binding that created this lease. Wire/copied settings grant nothing.
    assert.throws(() => processRetainedBodyIdentity(body, bindProcessStore(context)), {code: 'ForeignRetainedStoreBody'});
    assert.throws(() => processRetainedBodyIdentity(body, {...binding}), /ForeignProcessStoreBinding/);
    let admittedBytes = 0;
    assert.equal(await body.withVerifiedFile(async file => {
      assert.equal(admittedBytes, 2);
      assert.equal(await readFile(file.path, 'utf8'), '[]');
      return 'native-result';
    }, undefined, bytes => { admittedBytes += bytes; }), 'native-result');
    assert.equal(body.available(), true);
    body.close();
    assert.throws(() => processRetainedBodyIdentity(body, binding), {code: 'ForeignRetainedStoreBody'});
    assert.equal(store.body('task-1').available(), true);
    assert.equal(store.status().admittedWriteBytes, 2);
  } finally {
    lease.close(); await lease.cleanup(); stop(); await stopped;
    await store.close(); await store.cleanupHandle.retry(); await rmdir(parentDirectory);
  }
});
