import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {compileGeneratedGraphQueryJson, compileQueryJson,
  compileValuesQueryJson} from
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

test('node Graph pattern retains its explicit label selection', () => {
  const steps = [
    {values: {schema: {
      id: {type: 'number', nullable: false},
      entity_type: {type: 'string', nullable: true},
      name: {type: 'string', nullable: false},
    }, rows: [
      {id: 1, entity_type: 'Account', name: 'one'},
      {id: 2, entity_type: null, name: 'two'},
    ]}, as: 'nodes'},
    {values: {schema: {
      src: {type: 'number', nullable: false},
      dst: {type: 'number', nullable: false},
      rel: {type: 'string', nullable: true},
    }, rows: []}, as: 'edges'},
    {graph: {nodes: {from: 'nodes', id: 'id',
      fields: ['entity_type', 'name']},
    edges: {from: 'edges', source: 'src', target: 'dst',
      label: 'rel', fields: []}}, as: 'g'},
  ];
  const source = 'FROM GRAPH g LABELS {"node":{"field":"entity_type"}} '
    + '|> MATCH WALK (a:Account) |> SELECT a.name AS name';
  const wire = compileGeneratedGraphQueryJson(source, 'g',
    JSON.stringify(steps), JSON.stringify(['id', 'entity_type', 'name']),
    JSON.stringify(['src', 'dst', 'rel']), 'fixture.graph_node_only');
  assert.notEqual(wire, '');
  const program = JSON.parse(wire);
  assert.deepEqual(program.stages[0].steps.slice(0, 3), steps);
  assert.deepEqual(program.stages[0].steps[3],
    {from: 'g', node_rows: true, as: 'aql_graph_nodes_0'});
  assert.deepEqual(program.stages[0].steps[4].filter, {eq: [
    {field: 'entity_type'}, {literal: 'Account'}]});
  assert.deepEqual(program.stages[0].results.rows.fields, ['name']);
});
