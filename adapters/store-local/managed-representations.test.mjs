import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rmdir, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createLocalRetainedStore} from './files.mjs';
import {managedPhysicalRepresentation} from
  './managed-physical-representation.mjs';
import {
  registerManagedMemoryInput,
  managedInputPhysicalManifestCid,
  registerManagedInput,
  withManagedInputFiles,
  withManagedInputRows,
} from './managed-representations.mjs';

const codec = `sha256:${'1'.repeat(64)}`;
const fields = JSON.stringify([['id', 'DOUBLE', null, null]]);

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-managed-registry-'));
  const store = await createLocalRetainedStore({
    parentDirectory: directory,
    capacityBytes: 100,
    maxFrameBytes: 16,
  });
  t.after(async () => {
    store.close();
    await store.cleanup();
    await rmdir(directory);
  });
  const writer = store.reserve(100);
  await writer.start();
  await writer.appendBytes(Buffer.from('stored rows'));
  return {store, body: await writer.sealPhysical()};
}

test('managed registry binds exact manifest interpretation and generation', async t => {
  const {store, body} = await fixture(t);
  const material = {}, input = {};
  const representation = managedPhysicalRepresentation(
    body, 2, codec, fields, [0],
  );
  const admitted = registerManagedInput(
    material, value => value === input, store, body, codec,
    representation.manifest,
  );
  assert.equal(managedInputPhysicalManifestCid(material), admitted.cid);
  assert.equal(admitted.manifest.row_count, 2);
  const observed = await withManagedInputFiles([
    {material, input, codecContractCid: codec},
    {material, input, codecContractCid: codec},
  ], () => true, files => files.map(file => file.path));
  assert.equal(observed[0], observed[1]);

  const changedSchema = managedPhysicalRepresentation(
    body,
    2,
    codec,
    JSON.stringify([['other', 'DOUBLE', null, null]]),
    [0],
  );
  assert.notEqual(changedSchema.manifest.schema_contract_cid,
    representation.manifest.schema_contract_cid);
  assert.notEqual(changedSchema.cid, representation.cid);
});

test('managed registry rejects mismatched row, codec and chunk identity', async t => {
  const {store, body} = await fixture(t);
  const base = managedPhysicalRepresentation(body, 2, codec, fields, [0]);
  for (const manifest of [
    {...base.manifest, row_count: 3},
    {...base.manifest, codec_contract_cid: `sha256:${'2'.repeat(64)}`},
    {...base.manifest, chunks: [{
      ...base.manifest.chunks[0],
      cid: `sha256:${'3'.repeat(64)}`,
    }]},
  ]) {
    assert.throws(() => registerManagedInput(
      {}, () => true, store, body, codec, manifest,
    ), {code: 'InvalidManagedInputRegistration'});
  }
});

test('managed file commit runs after every final check and before pin release', async t => {
  const first = await fixture(t);
  const second = await fixture(t);
  const occurrences = [first, second].map(({store, body}) => {
    const material = {}, input = {};
    const representation = managedPhysicalRepresentation(
      body, 2, codec, fields, [0],
    );
    registerManagedInput(
      material, value => value === input, store, body, codec,
      representation.manifest,
    );
    return {material, input, codecContractCid: codec, store};
  });
  const events = [];
  const value = await withManagedInputFiles(
    occurrences,
    () => true,
    () => { events.push('use'); return 'provisional'; },
    undefined,
    undefined,
    provisional => {
      events.push('commit');
      assert.equal(provisional, 'provisional');
      assert.deepEqual(occurrences.map(value =>
        value.store.status().activeReaders), [1, 1]);
      return 'completed';
    },
  );
  events.push('returned');
  assert.equal(value, 'completed');
  assert.deepEqual(events, ['use', 'commit', 'returned']);
  assert.deepEqual(occurrences.map(value =>
    value.store.status().activeReaders), [0, 0]);
});

test('managed file final-check failure never enters commit', async t => {
  const first = await fixture(t);
  const second = await fixture(t);
  const occurrences = [first, second].map(({store, body}) => {
    const material = {}, input = {};
    const representation = managedPhysicalRepresentation(
      body, 2, codec, fields, [0],
    );
    registerManagedInput(
      material, value => value === input, store, body, codec,
      representation.manifest,
    );
    return {material, input, codecContractCid: codec};
  });
  let committed = false;
  await assert.rejects(withManagedInputFiles(
    occurrences,
    () => true,
    async files => {
      await writeFile(files[0].path, 'changed row');
      return 'provisional';
    },
    undefined,
    undefined,
    () => { committed = true; },
  ), error => ['RetainedBodyChanged', 'RetainedBodyTruncated']
    .includes(error?.code));
  assert.equal(committed, false);
});

test('managed file cancellation before final commit publishes nothing', async t => {
  const {store, body} = await fixture(t);
  const material = {}, input = {};
  const representation = managedPhysicalRepresentation(
    body, 2, codec, fields, [0],
  );
  registerManagedInput(
    material, value => value === input, store, body, codec,
    representation.manifest,
  );
  const cancel = new AbortController();
  let committed = false;
  await assert.rejects(withManagedInputFiles(
    [{material, input, codecContractCid: codec}],
    () => true,
    () => { cancel.abort(); return 'provisional'; },
    cancel.signal,
    undefined,
    () => { committed = true; },
  ), error => error?.name === 'AbortError');
  assert.equal(committed, false);
  assert.equal(store.status().activeReaders, 0);
});

test('pending native stop retains duplicate input pins until cleanup settles', async t => {
  const {store, body} = await fixture(t);
  const material = {}, input = {};
  const representation = managedPhysicalRepresentation(
    body, 2, codec, fields, [0],
  );
  registerManagedInput(
    material, value => value === input, store, body, codec,
    representation.manifest,
  );
  let stopped = false;
  const native = Object.freeze({
    status: () => Object.freeze({pending: !stopped}),
    retry: async () => { stopped = true; },
  });
  let failure;
  try {
    await withManagedInputFiles([
      {material, input, codecContractCid: codec},
      {material, input, codecContractCid: codec},
    ], () => true, () => {
      const error = new Error('cancel deadline');
      error.code = 'Cancelled';
      error.cleanupPending = true;
      error.cleanupHandle = native;
      throw error;
    });
  } catch (error) { failure = error; }
  assert.equal(failure.code, 'Cancelled');
  assert.equal(failure.primaryFailure.message, 'cancel deadline');
  assert.equal(store.status().activeReaders, 1,
    'duplicate logical inputs retain one physical borrow');
  body.close();
  assert.equal(await body.cleanupHandle.retry(), false);
  assert.equal(store.status().reservedBytes, body.bytes);
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(store.status().activeReaders, 0);
  await body.cleanupHandle.retry();
  assert.equal(store.status().reservedBytes, 0);
});

test('unknown native cleanup status cannot release an input pin', async t => {
  const {store, body} = await fixture(t);
  const material = {}, input = {};
  const representation = managedPhysicalRepresentation(
    body, 2, codec, fields, [0],
  );
  registerManagedInput(
    material, value => value === input, store, body, codec,
    representation.manifest,
  );
  let statusAvailable = false;
  const native = Object.freeze({
    status() {
      if (!statusAvailable) throw new Error('status unavailable');
      return Object.freeze({pending: false});
    },
    retry: async () => { statusAvailable = true; },
  });
  let failure;
  try {
    await withManagedInputFiles([
      {material, input, codecContractCid: codec},
    ], () => true, () => {
      const error = new Error('unconfirmed');
      error.cleanupPending = true;
      error.cleanupHandle = native;
      throw error;
    });
  } catch (error) { failure = error; }
  assert.equal(store.status().activeReaders, 1);
  assert.equal(failure.cleanupHandle.status().pending, true);
  await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.equal(store.status().activeReaders, 0);
  body.close();
  await body.cleanupHandle.retry();
});

test('managed memory close revokes new use and waits for the final scoped read', async () => {
  const material = {}, input = {};
  let sourceAvailable = true, releaseCount = 0, continueRead;
  const paused = new Promise(resolve => { continueRead = resolve; });
  let reading;
  const started = new Promise(resolve => { reading = resolve; });
  const memory = registerManagedMemoryInput(
    material,
    value => value === input,
    () => sourceAvailable,
    Object.freeze({
      async read(_file, emit) {
        reading();
        await paused;
        await emit('{"id":1}');
      },
    }),
    () => {
      sourceAvailable = false;
      releaseCount++;
    },
  );
  const rows = [];
  const active = withManagedInputRows(
    [{material, input}],
    value => value === input,
    (_index, row) => rows.push(row),
    () => 'completed',
  );
  await started;
  const closing = memory.close();
  assert.deepEqual(memory.status(), {
    open: false,
    readers: 1,
    released: false,
    releaseRequested: true,
    releaseAttempted: false,
    releaseFailed: false,
  });
  await assert.rejects(withManagedInputRows(
    [{material, input}],
    () => true,
    () => {},
    () => {},
  ), {code: 'ManagedInputUnavailable'});
  assert.equal(sourceAvailable, true,
    'the exact generation remains live for the admitted reader');
  continueRead();
  assert.equal(await active, 'completed');
  await closing;
  assert.deepEqual(rows, ['{"id":1}']);
  assert.deepEqual(memory.status(), {
    open: false,
    readers: 0,
    released: true,
    releaseRequested: true,
    releaseAttempted: true,
    releaseFailed: false,
  });
  assert.equal(releaseCount, 1);
  await memory.close();
  assert.equal(releaseCount, 1);
});

test('managed memory keeps its use until provider cleanup is confirmed', async () => {
  const material = {}, input = {};
  let stopped = false, releaseCount = 0;
  const native = Object.freeze({
    status: () => Object.freeze({pending: !stopped}),
    async retry() { stopped = true; return native.status(); },
  });
  const memory = registerManagedMemoryInput(
    material,
    value => value === input,
    () => true,
    Object.freeze({
      async read() {
        const failure = new Error('provider still stopping');
        failure.cleanupPending = true;
        failure.cleanupHandle = native;
        throw failure;
      },
    }),
    () => { releaseCount++; },
  );
  let failure;
  try {
    await withManagedInputRows(
      [{material, input}], () => true, () => {}, () => {},
    );
  } catch (error) { failure = error; }
  assert.equal(failure.primaryFailure.message, 'provider still stopping');
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal(memory.status().readers, 1);
  const closing = memory.close();
  assert.equal(memory.status().released, false);
  await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, false);
  await closing;
  assert.equal(memory.status().readers, 0);
  assert.equal(memory.status().released, true);
  assert.equal(releaseCount, 1);
});

test('managed memory cleanup releases only its own independent use', async () => {
  const material = {}, input = {};
  let stopped = false, releaseCount = 0, reads = 0;
  let continueSecond, secondStarted;
  const secondPaused = new Promise(resolve => { continueSecond = resolve; });
  const secondReading = new Promise(resolve => { secondStarted = resolve; });
  const native = Object.freeze({
    status: () => Object.freeze({pending: !stopped}),
    async retry() { stopped = true; return native.status(); },
  });
  const memory = registerManagedMemoryInput(
    material,
    value => value === input,
    () => true,
    Object.freeze({
      async read() {
        reads++;
        if (reads === 1) {
          const failure = new Error('first consumer still stopping');
          failure.cleanupPending = true;
          failure.cleanupHandle = native;
          throw failure;
        }
        secondStarted();
        await secondPaused;
      },
    }),
    () => { releaseCount++; },
  );
  let firstFailure;
  try {
    await withManagedInputRows(
      [{material, input}], () => true, () => {}, () => {},
    );
  } catch (error) { firstFailure = error; }
  const second = withManagedInputRows(
    [{material, input}], () => true, () => {}, () => 'second-complete',
  );
  await secondReading;
  assert.equal(memory.status().readers, 2);
  const closing = memory.close();
  await firstFailure.cleanupHandle.retry();
  assert.equal(memory.status().readers, 1,
    'confirming one consumer never releases the other consumer use');
  assert.equal(memory.status().released, false);
  assert.equal(releaseCount, 0);
  continueSecond();
  assert.equal(await second, 'second-complete');
  await closing;
  assert.equal(memory.status().readers, 0);
  assert.equal(memory.status().released, true);
  assert.equal(releaseCount, 1);
});

test('managed memory treats missing provider cleanup status as pending', async () => {
  const material = {}, input = {};
  let statusAvailable = false;
  const native = Object.freeze({
    status() {
      if (!statusAvailable) throw new Error('status unavailable');
      return Object.freeze({pending: false});
    },
    async retry() { statusAvailable = true; },
  });
  const memory = registerManagedMemoryInput(
    material, value => value === input, () => true,
    Object.freeze({
      async read() {
        const failure = new Error('unknown stop');
        failure.cleanupPending = true;
        failure.cleanupHandle = native;
        throw failure;
      },
    }),
    () => {},
  );
  let failure;
  try {
    await withManagedInputRows(
      [{material, input}], () => true, () => {}, () => {},
    );
  } catch (error) { failure = error; }
  assert.equal(memory.status().readers, 1);
  assert.equal(failure.cleanupHandle.status().pending, true);
  await failure.cleanupHandle.retry();
  assert.equal(memory.status().readers, 0);
  await memory.close();
});

test('managed memory release failure is not reported as confirmed', async () => {
  const material = {};
  let attempts = 0;
  const memory = registerManagedMemoryInput(
    material, () => true, () => true,
    Object.freeze({async read() {}}),
    () => { attempts++; throw new Error('release failed'); },
  );
  let failure;
  try { await memory.close(); }
  catch (error) { failure = error; }
  assert.equal(failure.code, 'ManagedInputReleaseFailed');
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.deepEqual(memory.status(), {
    open: false,
    readers: 0,
    released: false,
    releaseRequested: true,
    releaseAttempted: true,
    releaseFailed: true,
  });
  await failure.cleanupHandle.retry();
  assert.equal(attempts, 1, 'an arbitrary release callback is never retried');
  await assert.rejects(memory.close(), {code: 'ManagedInputReleaseFailed'});
});

test('managed memory records every throwable release cause on immediate close', async () => {
  for (const cause of [undefined, null, false, 0, '']) {
    const memory = registerManagedMemoryInput(
      {}, () => true, () => true,
      Object.freeze({async read() {}}),
      () => { throw cause; },
    );
    await assert.rejects(memory.close(), error => {
      assert.equal(error.code, 'ManagedInputReleaseFailed');
      assert.equal(Object.hasOwn(error, 'primaryFailure'), true);
      assert.equal(error.primaryFailure, cause);
      return true;
    });
    assert.deepEqual(memory.status(), {
      open: false,
      readers: 0,
      released: false,
      releaseRequested: true,
      releaseAttempted: true,
      releaseFailed: true,
    });
  }
});

test('managed memory records every throwable release cause after final use', async () => {
  for (const cause of [undefined, null, false, 0, '']) {
    const material = {}, input = {};
    let started, continueRead;
    const reading = new Promise(resolve => { started = resolve; });
    const paused = new Promise(resolve => { continueRead = resolve; });
    const memory = registerManagedMemoryInput(
      material, value => value === input, () => true,
      Object.freeze({
        async read() { started(); await paused; },
      }),
      () => { throw cause; },
    );
    const active = withManagedInputRows(
      [{material, input}], () => true, () => {}, () => 'done',
    ).then(() => undefined, error => error);
    await reading;
    const closing = memory.close().then(() => undefined, error => error);
    continueRead();
    for (const failure of [await active, await closing]) {
      assert.equal(failure.code, 'ManagedInputReleaseFailed');
      assert.equal(Object.hasOwn(failure, 'primaryFailure'), true);
      assert.equal(failure.primaryFailure, cause);
    }
    assert.equal(memory.status().releaseFailed, true);
  }
});

test('transient provider retry failure does not become cleanup ownership', async () => {
  const material = {}, input = {};
  let retries = 0, stopped = false, releaseCount = 0;
  const transient = new Error('first retry failed');
  const native = Object.freeze({
    status: () => Object.freeze({pending: !stopped}),
    async retry() {
      retries++;
      if (retries === 1) throw transient;
      stopped = true;
      return native.status();
    },
  });
  const memory = registerManagedMemoryInput(
    material, value => value === input, () => true,
    Object.freeze({
      async read() {
        const failure = new Error('provider still stopping');
        failure.cleanupPending = true;
        failure.cleanupHandle = native;
        throw failure;
      },
    }),
    () => { releaseCount++; },
  );
  let failure;
  try {
    await withManagedInputRows(
      [{material, input}], () => true, () => {}, () => {},
    );
  } catch (error) { failure = error; }
  const closing = memory.close();
  let state = await failure.cleanupHandle.retry();
  assert.equal(state.pending, true);
  assert.equal(state.errors.includes(transient), true);
  assert.equal(memory.status().readers, 1);
  state = await failure.cleanupHandle.retry();
  assert.equal(state.pending, false);
  assert.equal(state.errors.includes(transient), true,
    'transient retry failures remain diagnostic history only');
  assert.equal(memory.status().readers, 0);
  await closing;
  assert.equal(memory.status().released, true);
  assert.equal(releaseCount, 1);
});

test('managed memory attempts every input release after one fails', async () => {
  const inputs = [{material: {}, input: {}}, {material: {}, input: {}}];
  let continueRead;
  const paused = new Promise(resolve => { continueRead = resolve; });
  let started;
  const reading = new Promise(resolve => { started = resolve; });
  const releases = [0, 0];
  const registrations = inputs.map((entry, index) =>
    registerManagedMemoryInput(
      entry.material,
      value => value === entry.input,
      () => true,
      Object.freeze({
        async read() {
          if (index === 0) { started(); await paused; }
        },
      }),
      () => {
        releases[index]++;
        if (index === 1) throw new Error('second release failed');
      },
    ));
  const active = withManagedInputRows(
    inputs, () => true, () => {}, () => 'done',
  );
  await reading;
  const closes = registrations.map(value =>
    value.close().then(() => undefined, error => error));
  continueRead();
  await assert.rejects(active, error =>
    error.code === 'ManagedInputReleaseFailed' &&
    error.cleanupErrors.length === 1);
  const closeResults = await Promise.all(closes);
  assert.equal(closeResults[0], undefined);
  assert.equal(closeResults[1].code, 'ManagedInputReleaseFailed');
  assert.deepEqual(releases, [1, 1]);
  assert.equal(registrations[0].status().released, true);
  assert.equal(registrations[1].status().released, false);
});

test('zero-input managed row use executes and commits without a representation', async () => {
  const events = [];
  const value = await withManagedInputRows(
    [],
    () => assert.fail('zero-input execution has no authorization occurrence'),
    () => assert.fail('zero-input execution has no imported row'),
    () => {
      events.push('execute');
      return 'provisional';
    },
    undefined,
    () => assert.fail('zero-input execution has no physical read'),
    provisional => {
      events.push(['commit', provisional]);
      return 'completed';
    },
  );
  assert.equal(value, 'completed');
  assert.deepEqual(events, ['execute', ['commit', 'provisional']]);
});
