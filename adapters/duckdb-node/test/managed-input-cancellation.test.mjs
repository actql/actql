import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rmdir, stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createLocalRetainedStore} from '../../store-local/files.mjs';
import {
  registerManagedInput,
  withManagedInputFile,
} from '../../store-local/managed-representations.mjs';
import {managedPhysicalRepresentation} from
  '../../store-local/managed-physical-representation.mjs';
import {withComputeDatabase} from '../session.mjs';

const limits = Object.freeze({
  maxRows: 10,
  maxCells: 10,
  maxTransportBytes: 10000,
  maxSqlBytes: 10000,
  maxParameters: 2,
  maxColumns: 2,
  maxChunkRows: 10,
  maxChunkBytes: 4096,
  memoryBytes: 128 * 1024 * 1024,
  threads: 1,
  cancelWaitMs: 0,
});
const codec = `sha256:${'1'.repeat(64)}`;

test('DuckDB cancellation deadline retains input pin until actual session stop', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-managed-cancel-'));
  const store = await createLocalRetainedStore({
    parentDirectory: directory,
    capacityBytes: 1024,
    maxFrameBytes: 1024,
  });
  let body;
  let resume;
  const gate = new Promise(resolve => { resume = resolve; });
  let entered;
  const started = new Promise(resolve => { entered = resolve; });
  try {
    const writer = store.reserve(1024);
    await writer.start();
    await writer.append('[{"id":1}]');
    body = await writer.sealPhysical();
    const material = {}, input = {};
    registerManagedInput(
      material,
      value => value === input,
      store,
      body,
      codec,
      managedPhysicalRepresentation(
        body,
        1,
        codec,
        JSON.stringify([['id', 'DOUBLE', null, null]]),
        [0],
      ).manifest,
    );
    const controller = new AbortController();
    const pending = withManagedInputFile(
      material,
      input,
      codec,
      () => true,
      file => withComputeDatabase(
        limits,
        async session => {
          await session.command(
            'SELECT * FROM read_json_auto(?)',
            [{type: {id: 'VARCHAR'}, value: file.path}],
            () => {},
          );
          entered();
          await gate;
        },
        controller.signal,
        undefined,
        [file.path],
      ),
      controller.signal,
    );
    await started;
    controller.abort(new Error('deadline cancellation'));
    let failure;
    try { await pending; }
    catch (error) { failure = error; }
    assert.equal(failure.code, 'Cancelled');
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.equal(store.status().activeReaders, 1);
    body.close();
    assert.equal(await body.cleanupHandle.retry(), false);
    assert.equal(store.status().reservedBytes, body.bytes);
    resume();
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(store.status().activeReaders, 0);
    await body.cleanupHandle.retry();
    assert.equal(store.status().reservedBytes, 0);
  } finally {
    resume?.();
    body?.close();
    store.close();
    await store.cleanup();
    await rmdir(directory);
  }
});

test('Store reclaims unreported file after real DuckDB COPY stops', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-managed-copy-cancel-'));
  const store = await createLocalRetainedStore({
    parentDirectory: directory,
    capacityBytes: 4096,
    maxFrameBytes: 1024,
  });
  const writer = store.reserve(4096);
  const lease = writer.delegateCreate('cancelled-copy');
  try {
    await withComputeDatabase(
      {...limits, cancelWaitMs: undefined},
      session => session.copyParquet(
        'SELECT 1::DOUBLE AS id', [], lease.path,
      ),
      undefined,
      undefined,
      [lease.path],
    );
    assert((await stat(lease.path)).size > 0);
    writer.cancel();
    assert.equal(await writer.cleanupHandle.retry(), false);
    assert.equal(store.status().reservedBytes, 4096);
    assert.equal(writer.confirmDelegatedStopped(), true);
    store.close();
    assert.equal(await store.cleanup(), true);
    assert.equal(store.status().reservedBytes, 0);
    assert.equal(store.status().cleanupPending, false);
    await assert.rejects(stat(lease.path), {code: 'ENOENT'});
  } finally {
    writer.confirmDelegatedStopped();
    store.close();
    await store.cleanup();
    await rmdir(directory);
  }
});
