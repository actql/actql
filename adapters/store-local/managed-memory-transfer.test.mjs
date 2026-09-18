import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createManagedMemoryTransferProvider} from
  './managed-memory-transfer.mjs';
import {registerManagedMemoryInput, withManagedInputRows} from
  './managed-memory-representations.mjs';

function source(rows, estimate) {
  const material = {};
  const input = {};
  let released = false;
  const registration = registerManagedMemoryInput(
    material,
    value => value === input,
    () => !released,
    Object.freeze({
      async read(_file, emit, signal) {
        for (const row of rows) {
          signal?.throwIfAborted();
          await emit(row);
        }
      },
    }),
    () => { released = true; },
    estimate,
  );
  return {material, input, registration, released: () => released};
}

const estimate = Object.freeze({
  transferBytes: 4096n,
  retainedBytes: 16384n,
  executionBytes: 64n,
});

async function observeDestination(destination, input) {
  const rows = [];
  await withManagedInputRows(
    [{material: destination.material, input}],
    value => value === input,
    (_index, row) => { rows.push(row); },
    () => undefined,
  );
  return rows;
}

async function requirePreservedRows(provider, rows) {
  const original = source(rows, estimate);
  const destination = await provider.copy({
    sourceMaterial: original.material,
    input: original.input,
    authorize: value => value === original.input,
    destinationAuthorize: value => value === original.input,
    charge() {},
    estimate,
  });
  try {
    assert.deepEqual(await observeDestination(destination, original.input), rows);
  } catch (cause) {
    throw Object.assign(new Error('TransferPreservationFixtureMismatch'), {
      code: 'TransferPreservationFixtureMismatch',
      cause,
    });
  } finally {
    await destination.close();
    await original.registration.close();
  }
}

test('bounded transfer creates an independent destination generation', async () => {
  const original = source(['{"id":1}', '{"id":2}', '{"id":3}'], estimate);
  const charged = [];
  const provider = createManagedMemoryTransferProvider({
    maxBatchRows: 2,
    maxBatchBytes: 64,
  });
  let sourceAuthorized = true;
  assert.deepEqual(provider.estimate(original.material), estimate);
  const destination = await provider.copy({
    sourceMaterial: original.material,
    input: original.input,
    authorize: value => sourceAuthorized && value === original.input,
    destinationAuthorize: value => value === original.input,
    charge: bytes => charged.push(bytes),
    estimate,
  });
  assert.notEqual(destination.material, original.material);
  assert.equal(destination.rows, 3);
  assert.equal(destination.batches, 2);
  assert.equal(destination.maxBatchRows, 2);
  assert.equal(destination.maxBatchBytes, 64);
  assert.equal(destination.bytes,
    charged.reduce((sum, value) => sum + value, 0n));

  sourceAuthorized = false;
  await original.registration.close();
  assert.equal(original.released(), true);
  const observed = [];
  await withManagedInputRows(
    [{material: destination.material, input: original.input}],
    value => value === original.input,
    (_index, row) => { observed.push(row); },
    () => undefined,
  );
  assert.deepEqual(observed, ['{"id":1}', '{"id":2}', '{"id":3}']);
  await destination.close();
  assert.equal(destination.status().released, true);
});

test('independent preservation fixture detects value substitution and reordering', async () => {
  const rows = ['{"id":1,"t":"日本語"}', '{"id":1,"t":"日本語"}',
    '{"id":2,"t":"😀"}'];
  const conforming = createManagedMemoryTransferProvider({
    maxBatchRows: 2,
    maxBatchBytes: 128,
  });
  await requirePreservedRows(conforming, rows);

  for (const defect of ['substitute', 'reorder']) {
    const faulty = Object.freeze({
      ...conforming,
      async copy(options) {
        const destination = await conforming.copy(options);
        const observed = await observeDestination(destination, options.input);
        await destination.close();
        const changed = defect === 'substitute'
          ? ['{"id":9}', ...observed.slice(1)] : [...observed].reverse();
        const replacement = source(changed, estimate);
        const copied = await conforming.copy({
          ...options,
          sourceMaterial: replacement.material,
          input: replacement.input,
          authorize: value => value === replacement.input,
          destinationAuthorize: value => value === replacement.input,
        });
        const close = copied.close;
        return Object.freeze({
          ...copied,
          async close() {
            await close();
            await replacement.registration.close();
          },
        });
      },
    });
    await assert.rejects(requirePreservedRows(faulty, rows), {
      code: 'TransferPreservationFixtureMismatch',
    });
  }
});

test('transfer charges before retention and rejects a byte overrun', async () => {
  const limited = Object.freeze({...estimate, transferBytes: 7n});
  const original = source(['{"id":1}'], limited);
  const events = [];
  const provider = createManagedMemoryTransferProvider({
    maxBatchRows: 1,
    maxBatchBytes: 64,
  });
  await assert.rejects(provider.copy({
    sourceMaterial: original.material,
    input: original.input,
    authorize: () => true,
    destinationAuthorize: () => true,
    charge: bytes => events.push(bytes),
    estimate: limited,
  }), {code: 'ManagedTransferByteLimit'});
  assert.deepEqual(events, []);
  assert.equal(original.registration.status().readers, 0);
  await original.registration.close();
});

test('transfer counts exact UTF-8 bytes before bounded retention', async () => {
  const rows = [
    '{"t":"ASCII"}',
    '{"t":"日本語"}',
    '{"t":"😀"}',
    '{"t":"escaped\\n\\\"value"}',
  ];
  const exactBytes = rows.reduce((sum, row) =>
    sum + Buffer.byteLength(row, 'utf8'), 0);
  const exactEstimate = Object.freeze({
    transferBytes: BigInt(exactBytes),
    retainedBytes: 16384n,
    executionBytes: 128n,
  });
  const original = source(rows, exactEstimate);
  const charged = [];
  const provider = createManagedMemoryTransferProvider({
    maxBatchRows: rows.length,
    maxBatchBytes: exactBytes,
  });
  const destination = await provider.copy({
    sourceMaterial: original.material,
    input: original.input,
    authorize: value => value === original.input,
    destinationAuthorize: value => value === original.input,
    charge: bytes => charged.push(bytes),
    estimate: exactEstimate,
  });
  assert.equal(destination.bytes, BigInt(exactBytes));
  assert.equal(charged.reduce((sum, value) => sum + value, 0n),
    BigInt(exactBytes));
  assert.deepEqual(await observeDestination(destination, original.input), rows);
  await destination.close();
  await original.registration.close();
});

test('batch rejection does not allocate a row-sized UTF-8 array', async () => {
  const cell = 'a'.repeat(900 * 1024);
  const row = JSON.stringify(Object.fromEntries(
    Array.from({length: 9}, (_, index) => [`c${index}`, cell]),
  ));
  assert.ok(Buffer.byteLength(row, 'utf8') > 1024 * 1024);
  const largeEstimate = Object.freeze({
    transferBytes: BigInt(Buffer.byteLength(row, 'utf8')),
    retainedBytes: BigInt(row.length * 2 + 4096),
    executionBytes: 1024n * 1024n,
  });
  const original = source([row], largeEstimate);
  const provider = createManagedMemoryTransferProvider({
    maxBatchRows: 256,
    maxBatchBytes: 1024 * 1024,
  });
  const charged = [];
  await assert.rejects(provider.copy({
    sourceMaterial: original.material,
    input: original.input,
    authorize: () => true,
    destinationAuthorize: () => true,
    charge: bytes => charged.push(bytes),
    estimate: largeEstimate,
  }), {code: 'ManagedTransferBatchLimit'});
  assert.deepEqual(charged, []);
  assert.equal(original.registration.status().readers, 0);
  const implementation = await readFile(
    new URL('./managed-memory-transfer.mjs', import.meta.url), 'utf8');
  assert.doesNotMatch(implementation, /TextEncoder|\.encode\(row\)/);
  await original.registration.close();
});

test('transfer cancellation releases a stopped source use', async () => {
  const original = source(['{"id":1}', '{"id":2}'], estimate);
  const controller = new AbortController();
  const provider = createManagedMemoryTransferProvider({
    maxBatchRows: 1,
    maxBatchBytes: 64,
  });
  let charges = 0;
  await assert.rejects(provider.copy({
    sourceMaterial: original.material,
    input: original.input,
    authorize: () => true,
    destinationAuthorize: () => true,
    charge() {
      charges++;
      controller.abort();
    },
    signal: controller.signal,
    estimate,
  }), {name: 'AbortError'});
  assert.equal(charges, 1);
  assert.equal(original.registration.status().readers, 0);
  await original.registration.close();
});
