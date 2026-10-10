import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {traversalJoinSuccesses, traversalJoinRefusals, traversalJoinExecutionFailures} from './fixtures/traversal-join-source-input.mjs';

test('independent traversal controls distinguish node deduplication from path multiplicity through JOIN', () => {
  const cases = new Map(traversalJoinSuccesses.map(input => [input.name, input]));
  for (const emission of ['nodes', 'paths']) {
    const json = cases.get('traversal-join-' + emission + '-json');
    const text = cases.get('traversal-join-' + emission + '-text');
    assert.deepEqual(json.expected, text.expected);
    assert.equal(json.expected.length, emission === 'nodes' ? 2 : 4);
    const steps = JSON.parse(json.text).stages[0].steps;
    assert.deepEqual(steps.find(step => step.traverse).traverse,
      {start: {from: 'seeds', id: 'element'}, direction: 'out', min_hops: 2,
        max_hops: 2, path_mode: 'trail', emit: emission, max_output_rows: 10});
    assert.equal(steps.find(step => step.join).join.max_output_rows, 10);
    assert.deepEqual(steps.find(step => step.graph).graph.edges[0].key, ['edge_key']);
  }
  assert.deepEqual(cases.get('traversal-join-nodes-empty-selector').expected, []);
  assert.deepEqual(cases.get('traversal-join-paths-filter-limit').expected,
    [{depth: 2, tag: 10}, {depth: 2, tag: 10}, {depth: 2, tag: 20}]);
  assert.deepEqual(cases.get('traversal-join-nodes-column-order').columns.map(column => column.name), ['tag', 'depth']);
  assert.ok(traversalJoinExecutionFailures[0].text.includes('MAX_OUTPUT_ROWS 1'));
  const all = [...traversalJoinSuccesses, ...traversalJoinRefusals, ...traversalJoinExecutionFailures];
  assert.equal(new Set(all.map(input => input.name)).size, all.length);
});

test('traversal JOIN fixtures enter normal packed acceptance and its bounded public selection', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'traversalJoinSuccesses'], ['refusals', 'traversalJoinRefusals'],
    ['executionFailures', 'traversalJoinExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(fixture.match(/^const scopeOnly = (.+);$/mu)[1].split(/\s*\|\|\s*/u).includes('traversalJoinOnly'));
  assert.ok(fixture.includes('traversalJoinOnly ? {successes: traversalJoinSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_TRAVERSAL_JOIN_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/traversal-join-source-input.mjs', 'traversal-join-source-input.mjs']"));
  assert.ok(driver.includes("if (process.argv.includes('--traversal-join-only')) return;"));
});
