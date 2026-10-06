import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {graphDifferenceSourceSuccesses as successes, graphDifferenceSourceRefusals as refusals}
  from './fixtures/property-graph-difference-source-input.mjs';

test('Delta expectations retain separate parallel identities and complete contracts', () => {
  for (const item of successes) {
    assert.deepEqual(item.results.changes.columns,
      [{name: 'delta', contract: {type: 'json', nullable: false}}]);
    assert.equal(item.sourceReadCount, 0);
    if (!item.results.changes.rows.length) continue;
    const {delta} = item.results.changes.rows[0];
    assert.equal(delta.version, 'actql-graph-delta/0.1');
    assert.deepEqual(delta.nodes.add, []);
    assert.deepEqual(delta.edges.add, []);
    if (item.name.endsWith('removed')) {
      assert.equal(delta.nodes.remove.length, 1);
      assert.equal(delta.edges.remove.length, 2);
      assert.deepEqual(delta.edges.remove.map(row => row.key), [[10], [11]]);
      assert.notDeepEqual(delta.edges.remove[0].id, delta.edges.remove[1].id);
      assert.deepEqual(delta.edges.remove[0].src, delta.edges.remove[1].src);
      assert.deepEqual(delta.edges.remove[0].dst, delta.edges.remove[1].dst);
      assert.notEqual(delta.base_graph_cid, delta.target_graph_cid);
    } else {
      assert.deepEqual(delta.nodes.remove, []);
      assert.deepEqual(delta.edges.remove, []);
      assert.equal(delta.base_graph_cid, delta.target_graph_cid);
    }
  }
  assert.equal(successes.find(item => item.name.endsWith('empty-typed-relation'))
    .results.changes.rows.length, 0);
  assert.equal(refusals.length, 8);
  const removed = successes.find(item => item.name === 'graph-difference-json-parallel-removed');
  const steps = JSON.parse(removed.text).stages[0].steps;
  const construction = steps.find(step => step.property_graph).property_graph;
  for (const element of [...construction.nodes, ...construction.edges]) {
    assert.equal(element.labels[0].properties.mode, 'no_properties');
  }
  assert.ok(steps.some(step => step.subgraph?.nodes.from === 'selected'));
  assert.ok(steps.some(step => step.as === 'selected' && step.filter?.literal === false));
  assert.equal(steps.some(step => step.subtract_graphs), false);
});

test('ordinary packed corpus and narrow consumer retain the same authored Delta cases', () => {
  const consumer = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  assert.ok(consumer.includes('graphDifferenceOnly ? {successes: graphDifferenceSourceSuccesses, refusals: graphDifferenceSourceRefusals}'));
  assert.ok(consumer.includes('scopeInputs.successes.push(...graphDifferenceSourceSuccesses)'));
  assert.ok(consumer.includes('scopeInputs.refusals.push(...graphDifferenceSourceRefusals)'));
  const driver = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_GRAPH_DIFFERENCE_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/property-graph-difference-source-input.mjs', 'property-graph-difference-source-input.mjs']"));
  assert.ok(driver.includes("'--graph-equality-only', '--graph-difference-only',"));
});
