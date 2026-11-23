import assert from 'node:assert/strict';
import test from 'node:test';
import {encodeLocalCsvPage,prepareLocalCsvTable} from './local-csv-table.mjs';

const declaration = {path: 'small.csv', key: ['id'], columns: {id: 'int64', name: 'string'}};
const limits = {maxPathBytes: 100, maxDepth: 2, maxFileBytes: 256, maxPageBytes: 256,
  maxFiles: 3, maxPageRows: 3, maxBytes: 256, maxRows: 3, maxFieldBytes: 40};
const table = prepareLocalCsvTable('small', declaration, limits);
const decode = (text, overrides) => JSON.parse(encodeLocalCsvPage(Buffer.from(text), {...table, ...limits, ...overrides}, 1024));

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
  assert.throws(() => encodeLocalCsvPage(invalidEncoding, {...table,...limits}, 1024), {code:'InvalidLocalCsvEncoding'});
});

test('applies exact input, field and row limits and selects only the original root-relative file', () => {
  const data = 'id,name\n1,ABCD';
  assert.equal(decode(data, {maxBytes:data.length, maxFieldBytes:4, maxRows:1}).length, 1);
  assert.throws(() => decode(data, {maxBytes:data.length-1}), {code:'LocalCsvBytesLimit'});
  assert.throws(() => decode(data + 'E', {maxFieldBytes:4}), {code:'LocalCsvFieldLimit'});
  assert.throws(() => decode(data + '\n2,E', {maxRows:1}), {code:'LocalCsvRowsLimit'});
  for (const path of ['../small.csv','/small.csv','a//small.csv','a/b/c/small.csv','a\0.csv']) {
    assert.throws(() => prepareLocalCsvTable('small', {...declaration,path}, limits), {code:'InvalidLocalCsvPath'});
  }
  for (const key of [[], ['other'], ['id','id']]) {
    assert.throws(() => prepareLocalCsvTable('small', {...declaration,key}, limits), {code:'InvalidLocalCsvKey'});
  }
  assert.throws(() => prepareLocalCsvTable('small', {...declaration,columns:{id:'unknown'}}, limits),
    {code:'InvalidLocalCsvColumns'});
});

test('bounds expanded JSON output independently of the original file bytes', () => {
  const file = Buffer.from('id,name\n1,😀\n2,\t');
  const wire = '[{"id":"1","name":"😀"},{"id":"2","name":"\\t"}]';
  assert.equal(encodeLocalCsvPage(file, table, Buffer.byteLength(wire)),wire);
  assert.throws(() => encodeLocalCsvPage(file, table, Buffer.byteLength(wire)-1),
    {code:'LocalFilesPageBytesLimit'});
});
