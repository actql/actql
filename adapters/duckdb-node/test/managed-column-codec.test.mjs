import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DuckDBInstance} from '@duckdb/node-api';
import {encodeManagedColumnFrame,
  managedColumnCodecContractCid} from '../managed-column-codec.mjs';

const double = value => {
  const bytes = Buffer.alloc(8);
  bytes.writeDoubleBE(value);
  return bytes.toString('hex');
};
const fields = Object.freeze([
  Object.freeze({name: 'id', type: Object.freeze({id: 'DOUBLE'})}),
  Object.freeze({name: 'label', type: Object.freeze({id: 'VARCHAR'})}),
]);

test('managed column frames preserve bounded heterogeneous column occurrences', async () => {
  assert.match(managedColumnCodecContractCid, /^sha256:[0-9a-f]{64}$/);
  const frame = encodeManagedColumnFrame(fields,
    [[double(1), null, double(2)], ['x', null, '雪']], 3, 4);
  assert.equal(frame.toString('utf8'),
    '{"c0":[1,null,2],"c1":["x",null,"雪"],"o":[4,5,6]}\n');
  assert.throws(() => encodeManagedColumnFrame(fields,
    [[double(1)], ['x', 'y']], 1, 0), {code: 'UnsupportedManagedColumnFrame'});
  assert.throws(() => encodeManagedColumnFrame(fields,
    [[double(1)], ['x']], 1), {code: 'UnsupportedManagedColumnFrame'});
  assert.throws(() => encodeManagedColumnFrame(
    [{name: 'flag', type: {id: 'BOOLEAN'}}], [[true]], 1, 0),
  {code: 'UnsupportedManagedColumnFrame'});

  const directory = await mkdtemp(join(tmpdir(), 'actql-managed-column-'));
  const path = join(directory, 'body.ndjson');
  let instance, connection, prepared;
  try {
    await writeFile(path, frame);
    instance = await DuckDBInstance.create(':memory:');
    connection = await instance.connect();
    prepared = await connection.prepare(
      "SELECT unnest(c0), unnest(c1), unnest(o) " +
      "FROM read_json(?, format='newline_delimited', auto_detect=false, " +
      "columns={c0:'DOUBLE[]',c1:'VARCHAR[]',o:'BIGINT[]'}, ignore_errors=false)",
    );
    prepared.bindVarchar(1, path);
    const result = await prepared.runAndReadAll();
    assert.deepEqual(result.getRows(), [[1, 'x', 4n], [null, null, 5n], [2, '雪', 6n]]);
  } finally {
    prepared?.destroySync();
    connection?.closeSync();
    instance?.closeSync();
    await rm(directory, {recursive: true, force: true});
  }
});
