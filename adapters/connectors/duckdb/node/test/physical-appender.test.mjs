import test from 'node:test';
import assert from 'node:assert/strict';
import {DuckDBInstance, INTEGER, VARCHAR} from '@duckdb/node-api';
import {createPhysicalAppender} from '../physical-appender.mjs';
import {exportPhysicalValue, physicalType} from '../physical-values.mjs';

test('physical appender validates the whole row before native writes and poisons partial native failure', () => {
  const writes = [];
  const native = {columnCount: 2, columnType: i => i ? VARCHAR : INTEGER,
    appendInteger: value => writes.push(value), appendVarchar: value => writes.push(value),
    endRow: () => writes.push('end')};
  const row = [{type: {id: 'INTEGER'}, value: '3'}, {type: {id: 'VARCHAR'}, value: 'x'}];
  const adapter = createPhysicalAppender(native, 2);
  assert.throws(() => adapter.append([row[0], {type: {id: 'VARCHAR'}, value: 4}]),
    {code: 'InvalidPhysicalValue'});
  assert.throws(() => adapter.append([row[0], {type: {id: 'INTEGER'}, value: '4'}]),
    {code: 'ImportPhysicalType'});
  assert.deepEqual(writes, []);
  adapter.append(row);
  assert.deepEqual(writes, [3, 'x', 'end']);
  const charges = [];
  assert.throws(() => adapter.append([row[0], {type: {id: 'VARCHAR'}, value: 4}],
    bytes => charges.push(bytes)), {code: 'InvalidPhysicalValue'});
  assert.deepEqual(charges, []);
  assert.deepEqual(writes, [3, 'x', 'end']);
  assert.throws(() => adapter.append(row, () => { throw Error('budget'); }), /budget/);
  assert.deepEqual(writes, [3, 'x', 'end']);
  adapter.append(row, bytes => charges.push(bytes));
  assert.deepEqual(charges, [34]);
  assert.deepEqual(writes, [3, 'x', 'end', 3, 'x', 'end']);
  native.appendVarchar = () => { throw Error('native failure'); };
  assert.throws(() => adapter.append(row), /native failure/);
  assert.throws(() => adapter.append(row), {code: 'AppenderUnavailable'});
  adapter.invalidate();
  assert.throws(() => adapter.append(row), {code: 'AppenderUnavailable'});
});

test('bounded column chunks append complete rows and retain failure ownership', () => {
  const chunks = [];
  const native = {columnCount: 1, columnType: () => INTEGER,
    appendDataChunk: chunk => chunks.push(chunk.getColumnValues(0))};
  const adapter = createPhysicalAppender(native, 1, {rows: 2, bytes: 100});
  for (const value of ['1', '2', '3']) {
    adapter.append([{type: {id: 'INTEGER'}, value}]);
  }
  assert.deepEqual(chunks, [[1, 2]]);
  assert.throws(() => adapter.append([{type: {id: 'INTEGER'}, value: '4.0'}]),
    {code: 'InvalidPhysicalValue'});
  assert.deepEqual(chunks, [[1, 2]]);
  adapter.flush();
  assert.deepEqual(chunks, [[1, 2], [3]]);
  native.appendDataChunk = () => { throw Error('native chunk failure'); };
  adapter.append([{type: {id: 'INTEGER'}, value: '4'}]);
  assert.throws(() => adapter.flush(), /native chunk failure/);
  assert.throws(() => adapter.append([{type: {id: 'INTEGER'}, value: '5'}]),
    {code: 'AppenderUnavailable'});
});

test('real appender preserves adopted physical scalar extremes, null and duplicate order', async () => {
  const db = await DuckDBInstance.create(':memory:');
  const connection = await db.connect();
  let native;
  const parameters = [
    {type: {id: 'BOOLEAN'}, value: true},
    {type: {id: 'VARCHAR'}, value: '日本語😀'},
    {type: {id: 'BIGINT'}, value: '9223372036854775807'},
    {type: {id: 'UBIGINT'}, value: '18446744073709551615'},
    {type: {id: 'DECIMAL', precision: 38, scale: 2}, value: '99999999999999999999999999999999999999'},
    {type: {id: 'DATE'}, value: '-719162'},
    {type: {id: 'TIMESTAMP_TZ'}, value: '1789302896123456'},
    {type: {id: 'TIMESTAMP_NS'}, value: '1789302896123456789'},
    {type: {id: 'DOUBLE'}, value: '8000000000000000'},
    {type: {id: 'VARCHAR'}, value: null},
    {type: {id: 'TINYINT'}, value: '-128'},
    {type: {id: 'SMALLINT'}, value: '-32768'},
    {type: {id: 'INTEGER'}, value: '-2147483648'},
    {type: {id: 'HUGEINT'}, value: '-170141183460469231731687303715884105728'},
    {type: {id: 'UTINYINT'}, value: '255'},
    {type: {id: 'USMALLINT'}, value: '65535'},
    {type: {id: 'UINTEGER'}, value: '4294967295'},
    {type: {id: 'UHUGEINT'}, value: '340282366920938463463374607431768211455'},
    {type: {id: 'FLOAT'}, value: '80000000'},
    {type: {id: 'TIMESTAMP'}, value: '1789302896123456'},
    {type: {id: 'TIMESTAMP_S'}, value: '1789302896'},
    {type: {id: 'TIMESTAMP_MS'}, value: '1789302896123'},
  ];
  try {
    const columns = parameters.map(({type}, i) => `c${i} ${type.id === 'DECIMAL'
      ? `DECIMAL(${type.precision},${type.scale})` : type.id === 'TIMESTAMP_TZ' ? 'TIMESTAMPTZ' : type.id}`);
    await connection.run(`CREATE TEMP TABLE probe(${columns.join(', ')})`);
    native = await connection.createAppender('probe', 'main', 'temp');
    const appender = createPhysicalAppender(native, parameters.length,
      {rows: 2, bytes: 10000});
    appender.append(parameters);
    appender.append(parameters);
    appender.flush();
    appender.invalidate();
    native.closeSync();
    native = undefined;
    const result = await connection.runAndReadAll('SELECT * FROM probe');
    const fields = Array.from({length: result.columnCount}, (_, i) => physicalType(result.columnType(i)));
    const rows = result.getRows().map(row => row.map((cell, i) => exportPhysicalValue(cell, fields[i])));
    assert.deepEqual(fields, parameters.map(value => value.type));
    assert.deepEqual(rows, [parameters.map(value => value.value), parameters.map(value => value.value)]);
  } finally {
    try { native?.closeSync(); } finally {
      try { connection.closeSync(); } finally { db.closeSync(); }
    }
  }
});
