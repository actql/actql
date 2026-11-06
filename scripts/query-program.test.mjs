import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {groupedQueryCases} from './fixtures/grouped-query-programs.mjs';
import {canonicalText} from './check-canonical-json.mjs';
import {compileCapturedQueryJson as compileCapturedQueryWithCatalogJson, compileQueryJson,
  compileValuesQueryJson} from
  '../_build/js/debug/build/query_program_test_bridge/query_program_test_bridge.js';

const sourceEnvironment = JSON.parse(await readFile(new URL(
  '../adapters/host-node/fixtures/query-amount-environment.json', import.meta.url), 'utf8'));
const sourceEnvironmentWire = canonicalText(sourceEnvironment);
const sourceEnvironmentCid = sourceEnvironment.evidence_bundle_cid;
const compileCapturedQueryJson = (...args) => compileCapturedQueryWithCatalogJson(
  ...args, sourceEnvironmentWire, sourceEnvironmentCid);

const fixture = name => fileURLToPath(new URL(
  `../spec/frontend/fixtures/${name}`, import.meta.url));
const expected = JSON.parse(await readFile(fixture(
  'query-pair.expected-program.json'), 'utf8'));
const input = expected.stages[0].inputs.orders;
const fields = Object.keys(input.schema);
const sql = await readFile(fixture('query-pair.standard.sql'), 'utf8');
const pipe = await readFile(fixture('query-pair.pipe.sql'), 'utf8');

test('SQL and Pipe grouping preserve independent predicate and projection Programs', () => {
  for (const {name, source, expected: program} of groupedQueryCases) {
    const wire = compileCapturedQueryJson(source, 'records', 'remote',
      JSON.stringify({connector: 'crm/main', resource: 'r'}),
      JSON.stringify(['id', 'amount']), 'fixture.grouped_query');
    assert.notEqual(wire, '', name);
    assert.deepEqual(JSON.parse(wire), program, name);
  }
});

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

test('INFER KEEP and omitted KEEP match independent complete Program fixtures', async () => {
  const input = JSON.parse(await readFile(fixture('infer-keep/input.json'), 'utf8'));
  for (const name of ['kept', 'omitted']) {
    const text = await readFile(fixture(`infer-keep/${name}.aql`), 'utf8');
    const expected = JSON.parse(await readFile(
      fixture(`infer-keep/${name}.expected-program.json`), 'utf8'));
    const wire = compileValuesQueryJson(text, 'tickets', 'tickets',
      JSON.stringify(input), JSON.stringify(['id', 'text', 'secret']),
      'fixture.infer_keep');
    assert.notEqual(wire, '');
    const actual = JSON.parse(wire);
    assert.deepEqual(actual, expected);
    // Omitted KEEP is KEEP (*); explicit KEEP still has its authored subset.
    // These are public Result fields, independent of internal join-back slots.
    assert.deepEqual(actual.stages[0].results.rows.fields, name === 'omitted'
      ? ['id', 'text', 'secret', 'assessment'] : ['id', 'risk']);
    // Lowering emits no second Values/source acquisition or model egress from KEEP.
    assert.equal(expected.stages[0].steps.filter(step => step.values).length, 1);
    assert.deepEqual(actual.stages[0].steps.find(step => step.infer).infer.input,
      {text: {field: 'text'}});
  }
});

test('real-source CTE JOIN preserves one normal acquisition and shared producer', () => {
  const expected = {version: 'actql/0.1', id: 'fixture.cte_capture',
    stages: [
      {id: 'capture', inputs: {orders: input}, steps: [
        {from: 'orders', filter: {literal: true}},
        {select: fields, as: 'aql_capture_0'}],
      results: {source: {from: 'aql_capture_0', fields}}},
      // Captured JOINs use common Script lowering: one retained Source Result
      // feeds a single CTE producer used by both sides of the JOIN. Author this
      // complete machine expectation directly; never copy compiler output.
      {id: 'main', inputs: {orders: {result: {stage: 'capture', result: 'source'}}},
      steps: [{from: 'orders', select: ['id', 'amount'], as: 'aql_script_cte_1'},
      {from: 'aql_script_cte_1', join: {with: 'aql_script_cte_1', kind: 'inner',
        on: [{left: 'id', right: 'id'}], max_output_rows: 1000,
        select: {id: 'left.id'}}, as: 'aql_join_output_3'},
      {from: 'aql_join_output_3', sort: [{field: 'id', dir: 'asc', nulls: 'first'}],
        as: 'aql_join_sorted_9'}],
      results: {rows: {from: 'aql_join_sorted_9', fields: ['id']}}}],
    results: {answer: {from: {stage: 'main', result: 'rows'}}}};
  for (const predicate of ['', ' WHERE amount > 0']) {
    const authored = structuredClone(expected);
    if (predicate !== '') authored.stages[0].steps[0].filter =
      {gt: [{field: 'amount'}, {literal: 0}]};
    const wire = compileCapturedQueryJson(
      'WITH seed AS (SELECT id, amount FROM orders' + predicate + ') '
        + 'SELECT l.id AS id FROM seed l JOIN seed r ON l.id = r.id ORDER BY id',
      'orders', 'orders', JSON.stringify(input), JSON.stringify(fields),
      'fixture.cte_capture');
    assert.notEqual(wire, '');
    const actual = JSON.parse(wire);
    assert.deepEqual(actual, authored);
    assert.deepEqual(Object.keys(actual.stages[0].inputs), ['orders']);
    assert.deepEqual(actual.stages[0].inputs.orders, input);
    const computation = actual.stages[1];
    assert.deepEqual(computation.inputs,
      {orders: {result: {stage: 'capture', result: 'source'}}});
    const [producer, join] = computation.steps;
    assert.equal(computation.steps.filter(step => step.from === 'orders').length, 1);
    assert.equal(join.from, producer.as);
    assert.equal(join.join.with, producer.as);
  }
});

test('captured CTE and subquery compilation retains the original fixture Catalog', () => {
  const declaration = {connector: 'crm/main', resource: 'r'};
  const args = ['records', 'remote', JSON.stringify(declaration),
    JSON.stringify(['id', 'amount']), 'fixture.catalog_capture'];
  const queries = [
    'WITH chosen AS (SELECT id, amount FROM records WHERE id > 1) SELECT id FROM chosen',
    'SELECT outer_rows.id FROM (SELECT DISTINCT inner_rows.id FROM '
      + '(SELECT id FROM records WHERE id > 1) AS inner_rows '
      + 'ORDER BY id LIMIT 2) AS outer_rows',
    'WITH chosen AS (SELECT id, amount FROM records WHERE id > 1) '
      + 'SELECT l.id AS left_id, r.id AS right_id '
      + 'FROM chosen AS l JOIN chosen AS r ON l.id = r.id',
  ];
  for (const query of queries) {
    const wire = compileCapturedQueryJson(query, ...args);
    assert.notEqual(wire, '', query);
    const program = JSON.parse(wire);
    assert.equal(program.stages.length, 2);
    assert.deepEqual(program.stages[0].inputs.remote, declaration);
    assert.deepEqual(program.stages[1].inputs.remote,
      {result: {stage: 'capture', result: 'source'}});
    assert.equal(compileCapturedQueryWithCatalogJson(query, ...args,
      sourceEnvironmentWire, 'sha256:' + '0'.repeat(64)), '');
    assert.equal(compileCapturedQueryWithCatalogJson(query, ...args,
      '{}', sourceEnvironmentCid), '');
    assert.equal(compileCapturedQueryJson(query, ...[
      ...args.slice(0, 2), JSON.stringify({connector: 'foreign', resource: 'r'}), ...args.slice(3),
    ]), '');
  }
});
