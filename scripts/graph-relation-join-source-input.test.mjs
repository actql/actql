import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {graphRelationJoinSuccesses, graphRelationJoinRefusals, graphRelationJoinExecutionFailures} from './fixtures/graph-relation-join-source-input.mjs';
import {graphDifferenceSourceSuccesses} from './fixtures/graph-difference-source-input.mjs';

test('independent Graph Relation controls retain operation arguments, types, JOIN bounds and full Delta values', () => {
  const cases = new Map(graphRelationJoinSuccesses.map(item => [item.name, item]));
  for (const op of ['degree', 'components', 'graph_bounds', 'graphs_equal', 'match_nodes', 'match_edges']) {
    const json = cases.get('graph-relation-join-' + op + '-json');
    const text = cases.get('graph-relation-join-' + op + '-text');
    assert.deepEqual(json.expected, text.expected);
    assert.deepEqual(json.columns, text.columns);
    const steps = JSON.parse(json.text).stages[0].steps;
    assert.equal(steps.find(step => step.cross_join).cross_join.max_output_rows, 10);
    assert.ok(steps.find(step => Object.hasOwn(step, op)));
  }
  for (const format of ['json', 'aql-text']) {
    const fixture = cases.get('graph-relation-join-graph_diff-' + format);
    const value = fixture.expected[0].value;
    assert.deepEqual(Object.keys(value), ['$json']);
    const delta = value.$json;
    const original = graphDifferenceSourceSuccesses.find(item => item.name ===
      'graph-difference-' + (format === 'json' ? 'json-parallel-unchanged' : 'terminal-self'));
    assert.deepEqual(value, original.results.changes.rows[0].delta,
      'JOIN preserves the existing public typed cell without re-encoding it');
    assert.equal(delta.version, 'actql-graph-delta/0.1');
    assert.equal(delta.base_graph_cid, delta.target_graph_cid);
    for (const key of ['graph_contract_cid', 'base_graph_cid', 'target_graph_cid'])
      assert.match(delta[key], /^sha256:[0-9a-f]{64}$/u);
    assert.deepEqual(delta.nodes, {add: [], remove: [], update: []});
    assert.deepEqual(delta.edges, {add: [], remove: [], update: []});
    assert.deepEqual(fixture.expected[1].value, {$json: delta});
    assert.deepEqual(fixture.expected.map(row => row.tag), [10, 20]);
  }
  assert.deepEqual(cases.get('graph-relation-join-empty-match').expected, []);
  assert.deepEqual(cases.get('graph-relation-join-parameter-bounds').parameters, {p: 0});
  assert.deepEqual(cases.get('graph-relation-join-degree-filter-limit').expected, [{value: 1, tag: 10}]);
  assert.ok(graphRelationJoinExecutionFailures[0].text.includes('MAX_OUTPUT_ROWS 1'));
  const all = [...graphRelationJoinSuccesses, ...graphRelationJoinRefusals, ...graphRelationJoinExecutionFailures];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
});

test('Graph Relation JOIN fixtures enter normal packed acceptance and the focused transport cohort', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'graphRelationJoinSuccesses'], ['refusals', 'graphRelationJoinRefusals'],
    ['executionFailures', 'graphRelationJoinExecutionFailures']])
    assert.ok(fixture.includes('scopeInputs.' + kind + '.push(...' + group + ')'));
  assert.ok(fixture.match(/^const scopeOnly = (.+);$/mu)[1].split(/\s*\|\|\s*/u).includes('graphRelationJoinOnly'));
  assert.ok(fixture.includes('graphRelationJoinOnly ? {successes: graphRelationJoinSuccesses'));
  const preflight = driver.slice(driver.indexOf('console.log(run(process.execPath'),
    driver.indexOf("const packages = ['client-wire'"));
  for (const file of ['graph-difference-source-input.test.mjs',
    'graph-relation-join-source-input.test.mjs'])
    assert.ok(preflight.includes("'scripts/" + file + "'"), file);
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_GRAPH_RELATION_JOIN_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/graph-relation-join-source-input.mjs', 'graph-relation-join-source-input.mjs']"));
  assert.ok(driver.includes("if (process.argv.includes('--graph-relation-join-only')) return;"));
});
