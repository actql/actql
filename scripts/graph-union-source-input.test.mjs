import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {graphUnionProgram, graphUnionSourceSuccesses, graphUnionSourceRefusals,
  graphUnionSourceExecutionFailures} from './fixtures/graph-union-source-input.mjs';

test('union fixtures distinguish occurrences and nonassociative fold order', () => {
  const byName = new Map(graphUnionSourceSuccesses.map(x => [x.name, x]));
  assert.deepEqual(graphUnionProgram.stages[0].steps[3].union_graphs.with, ['g', 'g']);
  assert.deepEqual(byName.get('graph-union-repeated-peer-list-edges').results.edges.rows,
    [{w: 6, part: 7, edge_key: 10, labels: ['R']}, {w: 15, part: 7, edge_key: 11, labels: ['R']}]);
  assert.equal(byName.get('graph-union-forward-fold-order-nodes').results.nodes.rows[0].p, 8.75);
  assert.equal(byName.get('graph-union-reverse-fold-order-nodes').results.nodes.rows[0].p, 10.5);
  assert.deepEqual(JSON.parse(byName.get('graph-union-independent-json').text), graphUnionProgram);
  assert.ok(graphUnionSourceSuccesses.every(x => x.sourceReadCount === 0));
  const cases = [...graphUnionSourceSuccesses, ...graphUnionSourceRefusals, ...graphUnionSourceExecutionFailures];
  assert.equal(new Set(cases.map(x => x.name)).size, cases.length);
});

test('normal packed corpus retains union cases and narrow selection shares its driver', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'graphUnionSourceSuccesses'],
    ['refusals', 'graphUnionSourceRefusals'], ['executionFailures', 'graphUnionSourceExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(fixture.match(/const scopeOnly = ([^;]+);/u)?.[1].split(' || ').includes('graphUnionOnly'));
  assert.ok(fixture.includes('graphUnionOnly ? {successes: graphUnionSourceSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_GRAPH_UNION_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/graph-union-source-input.mjs', 'graph-union-source-input.mjs']"));
  const end = driver.slice(driver.indexOf('if (plannerSelectionOnly || twoSourceExampleOnly ||'));
  assert.match(end, /process\.argv\.includes\('--graph-union-only'\).*?return;/su);
});
