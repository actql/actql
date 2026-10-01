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

test('Pipe scopes lower to independently authored existing Program operations', () => {
  const values = {as: 'pair', values: {schema: {
    x: {type: 'number', nullable: false},
    y: {type: 'number', nullable: false}}, rows: [{x: 1, y: 20}, {x: 2, y: 10}]}};
  const cases = [
    {source: 'FROM pair AS before |> SET x = y |> AS later '
      + '|> SELECT later.x AS new_x, later.y AS y', fields: ['new_x', 'y'],
    steps: [{from: 'pair', derive: {aql_pipe_set_2: {field: 'y'}}},
      {select: [{new_x: 'aql_pipe_set_2'}, 'y'], as: 'aql_gen_0'}]},
    {source: 'FROM pair AS before |> SET x = y |> AS before '
      + '|> SELECT before.x AS new_x, before.y AS y', fields: ['new_x', 'y'],
    steps: [{from: 'pair', derive: {aql_pipe_set_2: {field: 'y'}}},
      {select: [{new_x: 'aql_pipe_set_2'}, 'y'], as: 'aql_gen_0'}]},
    {source: 'FROM pair AS before |> DROP x '
      + '|> SELECT before.x AS old_x, y', fields: ['old_x', 'y'],
    steps: [{from: 'pair', select: [{old_x: 'x'}, 'y'], as: 'aql_gen_0'}]},
    {source: 'FROM pair AS before |> RENAME x AS z '
      + '|> SELECT z AS new_x, before.x AS old_x', fields: ['new_x', 'old_x'],
    steps: [{from: 'pair', select: [{new_x: 'x'}, {old_x: 'x'}], as: 'aql_gen_0'}]},
  ];
  for (const {source, steps, fields} of cases) {
    const expected = {version: 'actql/0.1', id: 'fixture.pipe_scope',
      stages: [{id: 'main', inputs: {}, steps: [values, ...steps],
        results: {rows: {from: 'aql_gen_0', fields}}}],
      results: {answer: {from: {stage: 'main', result: 'rows'}}}};
    const actual = compileValuesQueryJson(source, 'pair', 'pair',
      JSON.stringify(values), JSON.stringify(['x', 'y']), 'fixture.pipe_scope');
    assert.notEqual(actual, '');
    assert.deepEqual(JSON.parse(actual), expected, source);
  }
});

test('rebound Pipe ORDER evaluates a current expression once and hides its slot', () => {
  const values = {as: 'pair', values: {schema: {
    x: {type: 'number', nullable: false}}, rows: [{x: 2}, {x: 1}]}};
  const expected = {version: 'actql/0.1', id: 'fixture.pipe_order_scope',
    stages: [{id: 'main', inputs: {}, steps: [values,
      {from: 'pair', select: ['x']},
      {filter: {gt: [{field: 'x'}, {literal: 0}]}},
      {derive: {aql_pipe_sort_2: {add: [{field: 'x'}, {literal: 1}]}}},
      {sort: [{field: 'aql_pipe_sort_2', dir: 'asc', nulls: 'first'},
        {field: 'aql_pipe_sort_2', dir: 'desc', nulls: 'last'}]},
      {select: ['x'], as: 'aql_gen_0'}],
    results: {rows: {from: 'aql_gen_0', fields: ['x']}}}],
    results: {answer: {from: {stage: 'main', result: 'rows'}}}};
  const source = 'FROM pair |> AS t |> SELECT x |> WHERE x > 0 '
    + '|> SELECT x |> ORDER BY x + 1, x + 1 DESC';
  const wire = compileValuesQueryJson(source, 'pair', 'pair',
    JSON.stringify(values), JSON.stringify(['x']), 'fixture.pipe_order_scope');
  assert.notEqual(wire, '');
  assert.deepEqual(JSON.parse(wire), expected);
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

test('INFER KEEP and omitted KEEP match independent complete Program fixtures', async () => {
  const input = JSON.parse(await readFile(fixture('infer-keep/input.json'), 'utf8'));
  for (const name of ['kept', 'omitted']) {
    const text = await readFile(fixture(`infer-keep/${name}.aql`), 'utf8');
    const expected = JSON.parse(await readFile(
      fixture(`infer-keep/${name}.expected-program.json`), 'utf8'));
    const actual = compileValuesQueryJson(text, 'tickets', 'tickets',
      JSON.stringify(input), JSON.stringify(['id', 'text', 'secret']),
      'fixture.infer_keep');
    assert.notEqual(actual, '');
    assert.deepEqual(JSON.parse(actual), expected);
    // Lowering emits no second Values/source acquisition or model egress from KEEP.
    assert.equal(expected.stages[0].steps.filter(step => step.values).length, 1);
    assert.deepEqual(expected.stages[0].steps.find(step => step.infer).infer.input,
      {text: {field: 'text'}});
  }
});

test('prepared packed INFER sources preserve authored visible fields and one invocation', async () => {
  const cases = JSON.parse(await readFile(
    fixture('infer-keep/packed-acceptance.json'), 'utf8'));
  for (const item of cases.successes) {
    const input = {as: 'tickets', values: {schema: cases.source_schema,
      rows: cases.source_rows[item.source_rows]}};
    const wire = compileValuesQueryJson(item.source, 'tickets', 'tickets',
      JSON.stringify(input), JSON.stringify(['id', 'text', 'secret']),
      'fixture.infer_keep');
    assert.notEqual(wire, '', item.name);
    const program = JSON.parse(wire);
    assert.deepEqual(program.stages[0].results.rows.fields,
      cases.columns[item.columns].map(column => column.name));
    assert.equal(program.stages[0].steps.filter(step => step.values).length, 1);
    const invocations = program.stages[0].steps.filter(step => step.infer);
    assert.equal(invocations.length, 1);
    assert.deepEqual(invocations[0].infer, {
      contract: 'model-task:risk-score.v1', key: 'id',
      input: {text: {field: 'text'}},
    });
  }
});
