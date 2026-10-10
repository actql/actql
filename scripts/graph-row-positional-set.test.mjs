import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {graphRowSourceSuccesses, graphRowSourceRefusals} from './fixtures/graph-row-source-input.mjs';

test('Graph row positional sets preserve authored NULL duplicates keys selectors and types', () => {
  const cases = new Map(graphRowSourceSuccesses.map(input => [input.name, input]));
  const node = cases.get('graph-row-node-set-json-control');
  assert.deepEqual(node.results.values.rows, [{value: null}, {value: null}, {value: 7}, {value: 8}]);
  for (const name of ['node-set-named', 'node-set-anonymous', 'node-set-unselected', 'node-set-data-head']) {
    assert.deepEqual(cases.get('graph-row-' + name).results, node.results);
    assert.equal(cases.get('graph-row-' + name).sourceReadCount, 0);
  }
  assert.deepEqual(cases.get('graph-row-node-set-head').results.answer, node.results.values);
  const edge = cases.get('graph-row-edge-set-json-control');
  assert.deepEqual(edge.results.values.rows, [{value: 10}, {value: 11}, {value: 11}, {value: 12}]);
  assert.deepEqual(cases.get('graph-row-edge-set-anonymous').results, edge.results);
  const program = JSON.parse(edge.text);
  const mapping = program.stages[0].steps.find(step => step.graph).graph;
  assert.deepEqual(mapping.edges[0].key, ['part', 'edge_key']);
  assert.deepEqual(program.stages[0].steps.find(step => step.edge_rows).edge_rows, {definition: 'E'});
  assert.equal(node.results.values.columns[0].contract.nullable, true);
  assert.equal(edge.results.values.columns[0].contract.nullable, false);
  assert.deepEqual(cases.get('graph-row-node-set-empty').results.values.rows, []);
  assert.equal(graphRowSourceRefusals.find(input => input.name.endsWith('set-anonymous-by-name')).expectedCode,
    'ClientProgramImplementationLimit');
  assert.equal(graphRowSourceRefusals.find(input => input.name.endsWith('set-anonymous-private-field')).expectedCode,
    'ClientProgramInvalidInput');
});

test('Graph row set cases remain registered in ordinary and focused packed consumers', () => {
  const consumer = readFileSync(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = readFileSync(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(consumer.includes('scopeInputs.successes.push(...graphRowSourceSuccesses)'));
  assert.ok(consumer.includes('scopeInputs.refusals.push(...graphRowSourceRefusals)'));
  assert.ok(consumer.includes('graphRowsOnly ? {successes: graphRowSourceSuccesses, refusals: graphRowSourceRefusals}'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_GRAPH_ROWS_ONLY = '1'"));
});
