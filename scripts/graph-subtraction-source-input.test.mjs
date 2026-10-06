import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {graphSubtractionProgram, graphSubtractionSubsetProgram,
  graphSubtractionSourceSuccesses, graphSubtractionSourceRefusals,
  graphSubtractionSourceExecutionFailures} from './fixtures/graph-subtraction-source-input.mjs';

test('subtraction expectations distinguish binary removal, property retention and endpoint closure', () => {
  const cases = new Map(graphSubtractionSourceSuccesses.map(c => [c.name, c]));
  assert.deepEqual(graphSubtractionProgram.stages[0].steps[3].subtract_graphs.with, 'g');
  assert.deepEqual(cases.get('graph-subtraction-self-default-removal-nodes').results.nodes.rows, []);
  assert.deepEqual(cases.get('graph-subtraction-explicit-equality-retains-node-nodes').results.nodes.rows,
    [{p: 7, part: 7, node_key: 1, labels: ['Person']}]);
  assert.deepEqual(cases.get('graph-subtraction-nonempty-subset-and-endpoint-closure-edges').results.edges.rows,
    [{w: 2, part: 7, edge_key: 10, labels: ['R']}]);
  assert.equal(graphSubtractionSubsetProgram.stages[0].steps[1].values.rows[0].dst_key, 2);
  const empty = cases.get('graph-subtraction-nullable-empty-contract-nodes').results.nodes;
  assert.deepEqual(empty.rows, []);
  assert.deepEqual(empty.columns[0], {name: 'p', contract: {type: 'number', nullable: true}});
  assert.equal(cases.get('graph-subtraction-zero-is-retained-value-nodes').results.nodes.rows[0].p, 0);
  assert.ok(cases.get('graph-subtraction-zero-is-retained-value-nodes').text.includes(
    'DATA n = SELECT 7 AS part, 1 AS node_key, 0 AS p;'));
  assert.ok(cases.get('graph-subtraction-nullable-empty-contract-nodes').text.includes(
    'DATA n = SELECT 7 AS part, 1 AS node_key, CAST(NULL AS FLOAT64) AS p;'));
  assert.ok(graphSubtractionSourceExecutionFailures.find(c => c.name === 'graph-subtraction-null-is-not-zero').text.includes(
    'DATA n = SELECT 7 AS part, 1 AS node_key, CAST(NULL AS FLOAT64) AS p;'));
  for (const kind of ['nodes', 'edges']) {
    assert.ok(cases.get('graph-subtraction-quoted-data-numeric-policy-' + kind).text.includes('with: `peer graph`'));
  }
  const all = [...graphSubtractionSourceSuccesses, ...graphSubtractionSourceRefusals,
    ...graphSubtractionSourceExecutionFailures];
  assert.equal(new Set(all.map(c => c.name)).size, all.length);
});

test('normal corpus and narrow subtraction run retain the same installed public driver', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'graphSubtractionSourceSuccesses'],
    ['refusals', 'graphSubtractionSourceRefusals'], ['executionFailures', 'graphSubtractionSourceExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(fixture.match(/const scopeOnly = ([^;]+);/u)?.[1].split(' || ').includes('graphSubtractionOnly'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_GRAPH_SUBTRACTION_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/graph-subtraction-source-input.mjs', 'graph-subtraction-source-input.mjs']"));
  assert.match(driver.slice(driver.indexOf('if (plannerSelectionOnly || twoSourceExampleOnly ||')),
    /process\.argv\.includes\('--graph-subtraction-only'\).*?return;/su);
});
