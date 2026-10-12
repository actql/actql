import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {graphMatchSourceSuccesses, graphMatchSourceRefusals} from './fixtures/graph-match-source-input.mjs';

const cases = new Map(graphMatchSourceSuccesses.map(c => [c.name, c]));

test('independent binding controls observe identities and distinct parallel-edge endpoints', () => {
  const node = cases.get('graph-match-node-binding-independent-json');
  const edge = cases.get('graph-match-edge-binding-independent-json');
  const n = JSON.parse(node.text).stages[0].steps;
  const e = JSON.parse(edge.text).stages[0].steps;
  assert.deepEqual(n[3].match_nodes.bindings, {identity: 'Element'});
  assert.deepEqual(e[3].match_edges.bindings, {identity: 'Edge', source: 'Source', target: 'Target'});
  assert.deepEqual(n[4].derive, {bound: {not: {is_null: {field: 'Element'}}}});
  assert.deepEqual(e[4].derive.source_bound, {not: {is_null: {field: 'Source'}}});
  assert.deepEqual(e[4].derive.target_bound, {not: {is_null: {field: 'Target'}}});
  assert.deepEqual(node.results.matched.rows, [
    {node_key: 1, p: 20, bound: true}, {node_key: 2, p: 10, bound: true}, {node_key: 3, p: null, bound: true},
  ]);
  assert.deepEqual(edge.results.matched.rows, [
    {edge_key: 10, weight: 20, bound: true, source_bound: true, target_bound: true},
    {edge_key: 11, weight: 10, bound: true, source_bound: true, target_bound: true},
  ]);
  assert.ok(graphMatchSourceSuccesses.every(c => c.sourceReadCount === 0));
});

test('uppercase and quoted binding sources retain their own named fields and empty contracts', () => {
  const node = cases.get('graph-match-node-uppercase-binding');
  const edge = cases.get('graph-match-edge-quoted-bindings');
  const empty = cases.get('graph-match-node-quoted-binding-empty');
  assert.ok(node.text.includes("BINDINGS: {IDENTITY: `Element`}"));
  assert.ok(edge.text.includes("`Source`: `Source`, `Target`: `Target`"));
  assert.deepEqual(node.results, cases.get('graph-match-node-binding-independent-json').results);
  assert.deepEqual(edge.results, cases.get('graph-match-edge-binding-independent-json').results);
  assert.deepEqual(empty.results.matched.rows, []);
  assert.deepEqual(empty.results.matched.columns, [
    {name: 'node_key', contract: {type: 'number', nullable: false}},
    {name: 'p', contract: {type: 'number', nullable: true}},
    {name: 'bound', contract: {type: 'boolean', nullable: false}},
  ]);
  const names = [...graphMatchSourceSuccesses, ...graphMatchSourceRefusals].map(c => c.name);
  assert.equal(new Set(names).size, names.length);
});

test('normal public corpus retains binding counterexamples and precise input refusals', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...graphMatchSourceSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...graphMatchSourceRefusals)'));
  assert.ok(fixture.includes('graphMatchOnly ? {successes: graphMatchSourceSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_GRAPH_MATCH_ONLY = '1'"));
  for (const suffix of ['duplicate-node-binding-role', 'duplicate-edge-binding-role', 'forbidden-node-binding-role', 'binding-output-collision']) {
    assert.equal(graphMatchSourceRefusals.find(c => c.name === 'graph-match-' + suffix).expectedCode,
      'ClientProgramInvalidInput');
  }
  for (const [name, expectedCode] of [
    ['graph-match-invalid-empty-fields', 'ClientProgramImplementationLimit'],
    ['graph-match-invalid-relation-is-not-graph', 'ClientProgramInvalidInput'],
  ]) {
    assert.equal(graphMatchSourceRefusals.find(c => c.name === name).expectedCode,
      expectedCode, name);
  }
});

test('each typed endpoint selector identifies a different original node and deduplicates parallel-edge starts', () => {
  for (const [role, p, node_key] of [['Source', 20, 1], ['Target', 10, 2]]) {
    const control = cases.get('graph-match-' + role.toLowerCase() + '-selector-independent-json');
    const source = cases.get('graph-match-' + role.toLowerCase() + '-binding-selector');
    assert.deepEqual(control.results.matched.rows, [{p, node_key}]);
    assert.deepEqual(source.results, control.results);
    const steps = JSON.parse(control.text).stages[0].steps;
    assert.deepEqual(steps[3].match_edges.bindings, {source: 'Source', target: 'Target'});
    assert.deepEqual(steps[4].subgraph, {nodes: {from: 'endpoints', id: role}});
    assert.deepEqual(steps[5].match_nodes, {definition: 'N', where: {literal: true}, fields: ['p', 'node_key']});
    assert.ok(source.text.includes("BINDINGS: {SOURCE: `Source`, `Target`: `Target`}"));
  }
});
