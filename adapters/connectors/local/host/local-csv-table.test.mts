import assert from 'node:assert/strict';
import test from 'node:test';
import {pathToFileURL} from 'node:url';
import {checked} from '../../../host-common/runtime-result.mjs';
import {encodeLocalCsvPage,prepareLocalCsvProjectEntry,type LocalCsvProjectRuntime,type LocalCsvRuntime} from './local-csv-table.mjs';

const moon = await import(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME === undefined
  ? new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url).href
  : pathToFileURL(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME).href) as LocalCsvRuntime & LocalCsvProjectRuntime & {
    clientProjectConnectionsAdmit(wire: string): unknown;
  };
const declaration = {path: 'small.csv', key: ['id'], columns: {id: 'int64', name: 'string'}};
const limits = {maxPathBytes: 100, maxDepth: 2, maxFileBytes: 256, maxPageBytes: 256,
  maxFiles: 3, maxPageRows: 3, maxBytes: 256, maxRows: 3, maxFieldBytes: 40};
const connections = (entry: unknown) => checked(moon.clientProjectConnectionsAdmit(JSON.stringify({
  version: 'actql-connectors/0.1', connections: {local: {connector: 'local', root: './data', tables: {small: entry}}},
})));
const select = (entry: unknown) => {
  const [table] = prepareLocalCsvProjectEntry(moon, connections(entry), 0, limits).tables;
  assert.ok(table);
  return table;
};
const table = select(declaration);
const decode = (text: string, overrides?: Partial<typeof limits>) => JSON.parse(encodeLocalCsvPage(moon, Buffer.from(text), {...table, ...limits, ...overrides}, 1024));

test('ordinary CSV projection preserves the original schema identity and ordered key', () => {
  assert.deepEqual(table.view, {
    resource:'small', resource_kind:'record',
    schema_wire:'{"id":{"nullable":false,"type":"int64"},"name":{"nullable":false,"type":"string"}}',
    schema_cid:'sha256:cb2f3b3b1ae90e17599f0ae3f8991a68796d8a94527353dbf832eb8eb4ebfe0c',
    facts_wire:'{"relation_keys":{"candidate_keys":[["id"]]}}',
  });
  assert.throws(() => prepareLocalCsvProjectEntry({}, connections(declaration), 0, limits),
    {code:'LocalCsvRuntimeUnavailable'});
});

test('decodes the declared CSV columns in file order with exact signed 64-bit values', () => {
  assert.deepEqual(decode('id,name\n1,A\n2,B\n3,C\n'), [
    {id: '1', name: 'A'}, {id: '2', name: 'B'}, {id: '3', name: 'C'},
  ]);
  assert.deepEqual(decode('\ufeffname,id\r\n"A, \"\"quoted\"\"\r\nline",-9223372036854775808\r\n,9223372036854775807'), [
    {id: '-9223372036854775808', name: 'A, "quoted"\r\nline'},
    {id: '9223372036854775807', name: ''},
  ]);
  assert.deepEqual(decode('id,name\n'), []);
});

test('rejects malformed CSV fields, wrong schemas and duplicates without coercion', () => {
  for (const [wire, code] of [
    ['id,id\n1,A', 'InvalidLocalCsvHeader'],
    ['id,other\n1,A', 'InvalidLocalCsvHeader'],
    ['id,name\n1,A,', 'InvalidLocalCsvWidth'],
    ['id,name\n1', 'InvalidLocalCsvWidth'],
    ['id,name\n1,"A', 'InvalidLocalCsvQuote'],
    ['id,name\n1,"A"x', 'InvalidLocalCsvSeparator'],
    ['id,name\n9223372036854775808,A', 'InvalidLocalCsvInt64'],
    ['id,name\n01,A', 'InvalidLocalCsvInt64'],
    ['id,name\n1,A\n1,B', 'DuplicateLocalCsvKey'],
  ]) assert.throws(() => decode(wire), {code});
  const invalidEncoding = Buffer.concat([Buffer.from('id,name\n1,'), Buffer.from([0xff])]);
  assert.throws(() => encodeLocalCsvPage(moon, invalidEncoding, {...table,...limits}, 1024), {code:'InvalidLocalCsvEncoding'});
});

test('applies exact input, field and row limits and selects only the original root-relative file', () => {
  const data = 'id,name\n1,ABCD';
  assert.equal(decode(data, {maxBytes:data.length, maxFieldBytes:4, maxRows:1}).length, 1);
  assert.throws(() => decode(data, {maxBytes:data.length-1}), {code:'LocalCsvBytesLimit'});
  assert.throws(() => decode(data + 'E', {maxFieldBytes:4}), {code:'LocalCsvFieldLimit'});
  assert.throws(() => decode(data + '\n2,E', {maxRows:1}), {code:'LocalCsvRowsLimit'});
  for (const path of ['../small.csv','/small.csv','a//small.csv','a/b/c/small.csv','a\0.csv']) {
    assert.throws(() => select({...declaration,path}), {code:'InvalidLocalCsvPath'});
  }
  for (const key of [[], ['other'], ['id','id']]) {
    assert.throws(() => select({...declaration,key}), {code:'InvalidLocalCsvKey'});
  }
  assert.throws(() => select({...declaration,columns:{id:'unknown'}}),
    {code:'InvalidLocalCsvColumns'});
});

test('bounds expanded JSON output independently of the original file bytes', () => {
  const file = Buffer.from('id,name\n1,😀\n2,\t');
  const wire = '[{"id":"1","name":"😀"},{"id":"2","name":"\\t"}]';
  assert.equal(encodeLocalCsvPage(moon, file, table, Buffer.byteLength(wire)),wire);
  assert.throws(() => encodeLocalCsvPage(moon, file, table, Buffer.byteLength(wire)-1),
    {code:'LocalFilesPageBytesLimit'});
});
