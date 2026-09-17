import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rmdir} from 'node:fs/promises';
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
  assert.deepEqual(memory.status(), {open: false, readers: 1, released: false});
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
  assert.deepEqual(memory.status(), {open: false, readers: 0, released: true});
  assert.equal(releaseCount, 1);
  await memory.close();
  assert.equal(releaseCount, 1);
});
