import assert from 'node:assert/strict';
import test from 'node:test';
import {bindPhysicalValue, exportPhysicalValue, physicalJsonScalarBytes,
  physicalType, PhysicalValueError} from '../physical-values.mjs';
import {DuckDBInstance, DuckDBTypeId} from '@duckdb/node-api';
import {boundedVectorItem} from '../bounded-vector.mjs';

test('physical scalar frame accounting matches encoded JSON bytes', () => {
  const values = [null, true, false, '', '0123456789abcdef', 'a/b',
    'quote"', 'back\\slash', 'line\nfeed', '\u0000', '\u007f',
    '日本語', 'é', '😀', '\ud800', '\udc00', 'a\ud83d\ude00z'];
  for (const value of values) {
    assert.equal(physicalJsonScalarBytes(value),
      Buffer.byteLength(JSON.stringify(value), 'utf8'),
      JSON.stringify(value));
  }
  assert.throws(() => physicalJsonScalarBytes(1),
    error => error instanceof PhysicalValueError && error.code === 'InvalidPhysicalValue');
});

test('floating physical transport preserves exact special bit patterns', () => {
  assert.equal(exportPhysicalValue(-0, {id: 'DOUBLE'}), '8000000000000000');
  assert.equal(exportPhysicalValue(-0, {id: 'FLOAT'}), '80000000');
  assert.equal(exportPhysicalValue(Infinity, {id: 'DOUBLE'}), '7ff0000000000000');
  assert.equal(exportPhysicalValue(-Infinity, {id: 'FLOAT'}), 'ff800000');
  assert.equal(exportPhysicalValue(1.5, {id: 'DOUBLE'}), '3ff8000000000000');
  assert.equal(exportPhysicalValue(1.5, {id: 'FLOAT'}), '3fc00000');
  // Alternating widths must not expose stale bytes from the shared scratch.
  assert.equal(exportPhysicalValue(-0, {id: 'DOUBLE'}), '8000000000000000');
});

test('fixed DuckDB double arrays retain component bits under typed vector transport', () => {
  const type = physicalType({typeId: DuckDBTypeId.ARRAY, length: 2,
    valueType: {typeId: DuckDBTypeId.DOUBLE}});
  assert.deepEqual(type, {id: 'DOUBLE_ARRAY', length: 2});
  const encoded = exportPhysicalValue({items: [1, -0]}, type);
  assert.equal(encoded, '3ff0000000000000,8000000000000000');
  assert.equal(physicalJsonScalarBytes(encoded),
    Buffer.byteLength(JSON.stringify(encoded), 'utf8'));
  assert.throws(() => exportPhysicalValue({items: [1]}, type),
    {code: 'InvalidPhysicalValue'});
  assert.throws(() => physicalType({typeId: DuckDBTypeId.ARRAY, length: 2,
    valueType: {typeId: DuckDBTypeId.VARCHAR}}),
  {code: 'UnsupportedPhysicalType'});
});

test('native fixed double array metadata and values reach the typed codec', async () => {
  const instance = await DuckDBInstance.create(':memory:');
  const connection = await instance.connect();
  try {
    const result = await connection.runAndReadAll('SELECT [1.0, 0.0]::DOUBLE[2] AS embedding');
    const type = physicalType(result.columnType(0));
    assert.deepEqual(type, {id: 'DOUBLE_ARRAY', length: 2});
    assert.equal(exportPhysicalValue(result.getRows()[0][0], type),
      '3ff0000000000000,0000000000000000');
  } finally {connection.closeSync(); instance.closeSync();}
});

test('oversized fixed arrays are rejected before native item materialization', () => {
  let read = false;
  assert.throws(() => boundedVectorItem({getItem() {read = true;}}, 0,
    {id: 'DOUBLE_ARRAY', length: 1000}, 64), {code: 'ChunkBytes'});
  assert.equal(read, false);
});

test('small integer and floating imports preserve canonical limits without per-cell buffers', () => {
  const observed = [];
  const sink = {
    bindInteger: (_index, value) => observed.push(value),
    bindUInteger: (_index, value) => observed.push(value),
    bindFloat: (_index, value) => observed.push(value),
    bindDouble: (_index, value) => observed.push(value),
  };
  bindPhysicalValue(sink, 1, {type: {id: 'INTEGER'}, value: '-2147483648'});
  bindPhysicalValue(sink, 1, {type: {id: 'UINTEGER'}, value: '4294967295'});
  bindPhysicalValue(sink, 1, {type: {id: 'FLOAT'}, value: '80000000'});
  bindPhysicalValue(sink, 1, {type: {id: 'DOUBLE'}, value: '3ff8000000000000'});
  bindPhysicalValue(sink, 1, {type: {id: 'FLOAT'}, value: '3fc00000'});
  assert.deepEqual(observed.slice(0, 2), [-2147483648, 4294967295]);
  assert(Object.is(observed[2], -0));
  assert.deepEqual(observed.slice(3), [1.5, 1.5]);
  for (const [id, value] of [
    ['INTEGER', '2147483648'], ['UINTEGER', '4294967296'],
    ['INTEGER', '-0'], ['INTEGER', '01'], ['INTEGER', '9007199254740993'],
    ['DOUBLE', '3FF8000000000000'], ['FLOAT', '3fc0000'],
  ]) {
    assert.throws(() => bindPhysicalValue(sink, 1, {type: {id}, value}),
      {code: 'InvalidPhysicalValue'});
  }
});
