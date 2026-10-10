import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {graphGraftProgram, graphGraftSourceSuccesses, graphGraftSourceRefusals,
  graphGraftSourceExecutionFailures} from './fixtures/graph-graft-source-input.mjs';

test('graft independent fixture preserves parallel self-loops and both Result consumers', () => {
  assert.deepEqual(graphGraftProgram.stages[0].steps[3],
    {from: 'g', graft_graph: {with: 'g'}, as: 'combined'});
  assert.deepEqual(Object.keys(graphGraftProgram.results).sort(), ['edges', 'nodes']);
  const expected = graphGraftSourceSuccesses[0].results;
  assert.deepEqual(expected.edges.rows.map(row => [row.edge_key, row.w]), [[10, 2], [11, 5]]);
  assert.deepEqual(expected.nodes.rows, [{p: 7, part: 7, node_key: 1, labels: ['Person']}]);
  assert.deepEqual(JSON.parse(graphGraftSourceSuccesses[0].text), graphGraftProgram);
  assert.deepEqual(graphGraftSourceSuccesses[1].results.edges.rows, []);
  assert.deepEqual(graphGraftSourceSuccesses[1].results.nodes.rows, []);
  const cases = [...graphGraftSourceSuccesses, ...graphGraftSourceRefusals,
    ...graphGraftSourceExecutionFailures];
  assert.equal(new Set(cases.map(item => item.name)).size, cases.length);
});

test('graft public fixtures reach the normal and narrow packed harness', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'graphGraftSourceSuccesses'],
    ['refusals', 'graphGraftSourceRefusals'], ['executionFailures', 'graphGraftSourceExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(fixture.match(/const scopeOnly = ([^;]+);/u)?.[1].split(' || ').includes('graphGraftOnly'));
  assert.ok(fixture.includes('graphGraftOnly ? {successes: graphGraftSourceSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_GRAPH_GRAFT_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/graph-graft-source-input.mjs', 'graph-graft-source-input.mjs']"));
});
