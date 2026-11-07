import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {graphRowsJoinSuccesses, graphRowsJoinRefusals, graphRowsJoinExecutionFailures} from './fixtures/graph-rows-join-source-input.mjs';

test('Graph row JOIN controls preserve keys, edge instances, multiplicity, explicit limits and shared capture', () => {
  const cases = new Map(graphRowsJoinSuccesses.map(input => [input.name, input]));
  for (const suffix of ['node-json', 'node-prefix', 'node-projected', 'node-cte']) {
    assert.deepEqual(cases.get('graph-rows-join-' + suffix).expected,
      [{node: 1, tag: 10}, {node: 1, tag: 20}, {node: 2, tag: 30}]);
  }
  const edge = JSON.parse(cases.get('graph-rows-join-edge-json').text);
  const mapping = edge.stages[0].steps.find(step => step.graph).graph;
  assert.deepEqual(mapping.edges[0].key, ['edge_key']);
  assert.deepEqual(mapping.edges[0].source, {definition: 'N', key: ['src_key']});
  assert.deepEqual(mapping.edges[0].target, {definition: 'N', key: ['dst_key']});
  assert.deepEqual(cases.get('graph-rows-join-edge-prefix').expected,
    [{edge: 10, tag: 10}, {edge: 10, tag: 20}, {edge: 11, tag: 30}]);
  for (const suffix of ['node-json', 'edge-json', 'shared-source-json']) {
    const control = JSON.parse(cases.get('graph-rows-join-' + suffix).text);
    const join = control.stages.flatMap(stage => stage.steps).find(step => step.join).join;
    assert.equal(join.kind, 'inner');
    assert.equal(join.max_output_rows, 10);
  }
  assert.deepEqual(cases.get('graph-rows-join-node-empty').expected, []);
  for (const suffix of ['shared-source-json', 'shared-source-text']) {
    assert.equal(cases.get('graph-rows-join-' + suffix).sourceReadSessionCount, 1);
    assert.equal(cases.get('graph-rows-join-' + suffix).sourceReadCount, 1);
    assert.deepEqual(cases.get('graph-rows-join-' + suffix).columns,
      [{name: 'node', contract: {type: 'number', nullable: false}},
        {name: 'tag', contract: {type: 'number', nullable: true}},
        {name: 'value', contract: {type: 'number', nullable: true}}]);
  }
  assert.ok(graphRowsJoinExecutionFailures[0].text.includes('MAX_OUTPUT_ROWS 2'));
  assert.equal(graphRowsJoinRefusals.find(input => input.name.endsWith('shadowed-graph')).expectedCode,
    'ClientProgramInvalidInput');
  const all = [...graphRowsJoinSuccesses, ...graphRowsJoinRefusals, ...graphRowsJoinExecutionFailures];
  assert.equal(new Set(all.map(input => input.name)).size, all.length);
});

test('Graph row JOIN fixtures enter ordinary packed acceptance and its bounded selection', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'graphRowsJoinSuccesses'], ['refusals', 'graphRowsJoinRefusals'],
    ['executionFailures', 'graphRowsJoinExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(fixture.match(/^const scopeOnly = (.+);$/mu)[1].split(/\s*\|\|\s*/u).includes('graphRowsJoinOnly'));
  assert.ok(fixture.includes('graphRowsJoinOnly ? {successes: graphRowsJoinSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_GRAPH_ROWS_JOIN_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/graph-rows-join-source-input.mjs', 'graph-rows-join-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--graph-rows-join-only'/u);
  assert.ok(driver.includes("if (process.argv.includes('--graph-rows-join-only')) return;"));
});

// Authored predecessor bytes are evidence, not product-derived expectations.
test('WITH Graph row JOIN retirement preserves independent values, controls and custody counts', async () => {
  const retained = JSON.parse(await readFile(new URL('../reviews/2026-10-11-with-carrier-cutover/with-graph-carrier-public-original-fixtures.json', import.meta.url), 'utf8'));
  const original = retained.files['scripts/fixtures/graph-rows-join-source-input.mjs'].text;
  const old = await import('data:text/javascript;base64,' + Buffer.from(original).toString('base64'));
  assert.deepEqual(graphRowsJoinSuccesses.map(({text, ...item}) => item), old.graphRowsJoinSuccesses.map(({text, ...item}) => item));
  for (let index = 0; index < graphRowsJoinSuccesses.length; index++) {
    const item = graphRowsJoinSuccesses[index];
    if (item.format === 'json') assert.equal(item.text, old.graphRowsJoinSuccesses[index].text);
    else {
      assert.match(item.text, /^WITH /);
      assert.doesNotMatch(item.text, /\bDATA\b|PROPERTY GRAPH/);
      assert.match(item.text, /MAX_OUTPUT_ROWS 10/);
    }
  }
  assert.deepEqual(graphRowsJoinRefusals.map(({text, expectedCode, ...item}) => item), old.graphRowsJoinRefusals.map(({text, expectedCode, ...item}) => item));
  const retainedFailures = old.graphRowsJoinExecutionFailures.map(({text, ...item}) =>
    item.name === 'graph-rows-join-explicit-bound-exceeded' ? {...item, resultNames: ['main']} : item);
  assert.deepEqual(graphRowsJoinExecutionFailures.map(({text, ...item}) => item), retainedFailures);
  assert.equal(graphRowsJoinSuccesses.length, 10);
  assert.equal(graphRowsJoinRefusals.length, 5);
  assert.equal(graphRowsJoinExecutionFailures.length, 1);
});
