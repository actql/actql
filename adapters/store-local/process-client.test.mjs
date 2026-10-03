import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rmdir, readFile, lstat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {bindProcessStore} from './process-binding.mjs';
import {createProcessStoreLease, processRetainedBodyIdentity} from './process-client.mjs';
import {createProcessRetainedStore} from './process-service.mjs';
import {registerRetainedInput, retainedStorageBody} from './representations.mjs';

async function snapshotLeaseFixture(t, intercept = async (_request, reply) => reply) {
  const parentDirectory = await mkdtemp(join(tmpdir(), 'actql-snapshot-lease-'));
  const store = createProcessRetainedStore({parentDirectory, capacityBytes: 8,
    maxFrameBytes: 8, maxEntries: 2});
  const identity = {session: 'snapshot-session', run: 'original-run'};
  let stop;
  const stopped = new Promise(resolve => { stop = resolve; });
  store.observe({identity: () => identity, cleanupHandle: {whenStopped: () => stopped}});
  const controller = new AbortController();
  let calls = 0;
  const binding = bindProcessStore({...identity, callHost: async request => {
    const reply = await store.service.invoke(request, controller.signal,
      {...identity, sequence: 1, call: ++calls});
    return intercept(request, reply);
  }});
  const leases = [];
  t.after(async () => {
    for (const lease of leases) { lease.close(); await lease.cleanup(); }
    stop(); await stopped;
    await store.close(); await store.cleanupHandle.retry(); await rmdir(parentDirectory);
  });
  return {store, identity, controller,
    async save(key) {
      const lease = createProcessStoreLease(binding, key, 8, 8, controller.signal);
      leases.push(lease);
      const writer = lease.reserve(8);
      await writer.start();
      await writer.append('[]');
      const cid = `sha256:${createHash('sha256').update('[]').digest('hex')}`;
      const body = await writer.seal({cid, bytes: 2});
      return {lease, body, path: body.nativeFilePath(), cid};
    },
  };
}

test('sealed snapshot release verifies exact identity and reclaims parent file and capacity once', async t => {
  const {store, identity, controller, save} = await snapshotLeaseFixture(t);
  const first = await save('snapshot-1');
  assert.equal(await readFile(first.path, 'utf8'), '[]');
  await assert.rejects(store.service.invoke({command: 'release-sealed', output: 'snapshot-1',
    report: {bytes: 2, cid: `sha256:${'0'.repeat(64)}`}}, controller.signal, identity),
  {code: 'ForeignStoreReport'});
  assert.equal(store.body('snapshot-1').available(), true);
  assert.equal(store.status().reservedBytes, 2);
  await assert.rejects(store.service.invoke({command: 'release-sealed', output: 'snapshot-1',
    report: {bytes: 2, cid: first.cid}}, controller.signal, {...identity, run: 'another-run'}),
  {code: 'ForeignStoreSession'});
  assert.equal(store.body('snapshot-1').available(), true);
  await first.body.withVerifiedFile(file => readFile(file.path, 'utf8'));
  assert.deepEqual(await first.lease.release(), {pending: false});
  assert.equal(first.lease.status().reservedBytes, 0);
  assert.equal(first.lease.status().cleanupPending, false);
  assert.equal(store.status().reservedBytes, 0);
  await assert.rejects(lstat(first.path), {code: 'ENOENT'});
  assert.deepEqual(await first.lease.release(), {pending: false});
  const second = await save('snapshot-2');
  assert.equal(store.status().reservedBytes, 2);
  assert.deepEqual(await second.lease.release(), {pending: false});
  assert.equal(store.status().admittedWriteBytes, 4);
  assert.equal(store.status().reservedBytes, 0);
  // Released output names remain bounded tombstones, not reusable generations.
  await assert.rejects(save('snapshot-1'), {code: 'InvalidStoreRequest'});
  await assert.rejects(save('snapshot-3'), {code: 'InvalidStoreRequest'});
});

test('snapshot release waits for actual verified-reader completion', async t => {
  const {store, save} = await snapshotLeaseFixture(t);
  const {lease, body, path} = await save('reading');
  let entered, finish;
  const started = new Promise(resolve => { entered = resolve; });
  const held = new Promise(resolve => { finish = resolve; });
  const reading = body.withVerifiedFile(async file => {
    assert.equal(await readFile(file.path, 'utf8'), '[]');
    entered();
    await held;
  });
  const observed = reading.then(() => undefined, error => error);
  try {
    await started;
    assert.deepEqual(await lease.release(), {pending: true});
    assert.equal(store.status().activeReaders, 1);
    assert.equal(store.status().reservedBytes, 2);
    assert.equal((await lstat(path)).size, 2);
    assert.equal(lease.status().cleanupPending, true);
    finish();
    assert.equal((await observed).code, 'RetainedUnavailable');
    assert.equal(store.status().activeReaders, 0);
    assert.deepEqual(await lease.release(), {pending: false});
    await assert.rejects(lstat(path), {code: 'ENOENT'});
    assert.equal(store.status().reservedBytes, 0);
  } finally {
    finish(); await observed;
  }
});

test('lost or invalid release ACK retains custody and retries the same parent body', async t => {
  for (const mode of ['lost', 'invalid']) {
    let first = true, releaseCalls = 0;
    const {store, save} = await snapshotLeaseFixture(t, async (request, reply) => {
      if (request.command !== 'release-sealed') return reply;
      releaseCalls++;
      if (!first) return reply;
      first = false;
      if (mode === 'lost') throw Object.assign(new Error('ReleaseAckLost'), {code: 'ReleaseAckLost'});
      return {...reply, cid: `sha256:${'0'.repeat(64)}`};
    });
    const {lease, path} = await save(`ack-${mode}`);
    await assert.rejects(lease.release(), {code: mode === 'lost' ? 'ReleaseAckLost' : 'ForeignStoreReleaseReport'});
    // The parent reclaimed physically; the child cannot infer that from a failure.
    assert.equal(store.status().reservedBytes, 0);
    await assert.rejects(lstat(path), {code: 'ENOENT'});
    assert.equal(lease.status().cleanupPending, true);
    assert.equal(lease.status().reservedBytes, 8);
    await lease.cleanup();
    assert.equal(lease.status().cleanupPending, false);
    assert.equal(lease.status().reservedBytes, 0);
    assert.equal(releaseCalls, 2);
    assert.equal(store.status().admittedWriteBytes, 2);
    await lease.release();
    assert.equal(releaseCalls, 2);
  }
});

test('accepted seal with a lost reply is released from its original report without re-sealing', async t => {
  const parentDirectory = await mkdtemp(join(tmpdir(), 'actql-snapshot-seal-loss-'));
  const store = createProcessRetainedStore({parentDirectory, capacityBytes: 8, maxFrameBytes: 8, maxEntries: 1});
  const identity = {session: 'snapshot-seal-session', run: 'original-run'};
  let stop;
  const stopped = new Promise(resolve => { stop = resolve; });
  store.observe({identity: () => identity, cleanupHandle: {whenStopped: () => stopped}});
  const controller = new AbortController(), commands = [];
  const binding = bindProcessStore({...identity, callHost: async request => {
    commands.push(request.command);
    const reply = await store.service.invoke(request, controller.signal, identity);
    if (request.command === 'seal') throw Object.assign(new Error('SealAckLost'), {code: 'SealAckLost'});
    return reply;
  }});
  const lease = createProcessStoreLease(binding, 'original-snapshot', 8, 8, controller.signal);
  t.after(async () => {
    lease.close(); await lease.cleanup(); stop(); await stopped;
    await store.close(); await store.cleanupHandle.retry(); await rmdir(parentDirectory);
  });
  const writer = lease.reserve(8);
  await writer.start();
  await writer.append('[]');
  await assert.rejects(writer.sealPhysical(), {code: 'SealAckLost'});
  assert.equal(store.body('original-snapshot').available(), true);
  assert.equal(store.status().reservedBytes, 2);
  assert.deepEqual(await lease.release(), {pending: false});
  assert.equal(store.body('original-snapshot').available(), false);
  assert.equal(store.status().reservedBytes, 0);
  assert.deepEqual(commands, ['reserve', 'seal', 'release-sealed']);
  assert.equal(store.status().admittedWriteBytes, 2);
});

test('parallel snapshot releases share the same physical reclamation request', async t => {
  let calls = 0, finish;
  const held = new Promise(resolve => { finish = resolve; });
  const {store, save} = await snapshotLeaseFixture(t, async (request, reply) => {
    if (request.command === 'release-sealed') { calls++; await held; }
    return reply;
  });
  const {lease} = await save('parallel');
  const first = lease.release(), second = lease.release();
  try {
    finish();
    assert.deepEqual(await Promise.all([first, second]), [{pending: false}, {pending: false}]);
    assert.equal(calls, 1);
    assert.equal(store.status().reservedBytes, 0);
    assert.equal(store.status().admittedWriteBytes, 2);
  } finally { finish(); }
});

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
