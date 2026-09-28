import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {compileQueryJson, compileValuesQueryJson} from
  '../_build/js/debug/build/query_program_test_bridge/query_program_test_bridge.js';

const fixture = name => fileURLToPath(new URL(
  `../spec/frontend/fixtures/${name}`, import.meta.url));
const expected = JSON.parse(await readFile(fixture(
  'query-pair.expected-program.json'), 'utf8'));
const input = expected.stages[0].inputs.orders;
const fields = Object.keys(input.schema);
const sql = await readFile(fixture('query-pair.standard.sql'), 'utf8');
const pipe = await readFile(fixture('query-pair.pipe.sql'), 'utf8');

test('independent SQL and Pipe pair lower to the same admitted Program', () => {
  for (const source of [sql, pipe]) {
    const wire = compileQueryJson(source, 'orders', 'orders',
      JSON.stringify(input), JSON.stringify(fields), 'fixture.query_pair');
    assert.notEqual(wire, '');
    assert.deepEqual(JSON.parse(wire), expected);
  }
});

test('query pair can bind admitted source-free Values for the Host', async () => {
  const rows = (await readFile(fixture('orders.jsonl'), 'utf8')).trim()
    .split('\n').map(line => JSON.parse(line));
  const values = {values: {schema: input.schema, rows}, as: 'orders'};
  const wire = compileValuesQueryJson(sql, 'orders', 'orders',
    JSON.stringify(values), JSON.stringify(fields), 'fixture.query_pair');
  assert.notEqual(wire, '');
  const program = JSON.parse(wire);
  assert.deepEqual(program.stages[0].inputs, {});
  assert.deepEqual(program.stages[0].steps[0], values);
  assert.deepEqual(program.stages[0].steps.slice(1), expected.stages[0].steps);
  assert.deepEqual(program.results, expected.results);
});
