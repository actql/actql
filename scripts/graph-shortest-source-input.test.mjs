import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {graphShortestSourceSuccesses, graphShortestSourceRefusals}
  from './fixtures/graph-shortest-source-input.mjs';

test('Shortest oracles preserve zero-hop, independent identities and all selection modes', () => {
  const machine = graphShortestSourceSuccesses[0];
  const program = JSON.parse(machine.text);
  const body = program.stages[0].steps[2].shortest_path;
  assert.deepEqual(Object.keys(program.results).sort(), ['a', 'b']);
  assert.equal(Object.hasOwn(body, 'selection'), false);
  assert.deepEqual(machine.results.a, machine.results.b);
  assert.deepEqual(machine.results.a.rows, [{source_id: {$json: body.source},
    target_id: {$json: body.target}, total_cost: 0, hop_count: 0,
    node_ids: [{$json: body.source}], edge_ids: []}]);
  for (const selection of ['each_pair', 'nearest_per_source', 'nearest_pair']) {
    const sample = graphShortestSourceSuccesses.find(x => x.name.endsWith(selection));
    assert.ok(sample.text.includes("selection: '" + selection + "'"));
    assert.equal(sample.results.paths.rows.length, 1);
  }
  const empty = graphShortestSourceSuccesses.find(x => x.name.includes('empty-target'));
  assert.deepEqual(empty.results.paths.rows, []);
  assert.deepEqual(empty.results.paths.columns, machine.results.a.columns);
  const all = [...graphShortestSourceSuccesses, ...graphShortestSourceRefusals];
  assert.equal(all.length, 12);
  assert.equal(new Set(all.map(x => x.name)).size, all.length);
  const weighted = graphShortestSourceSuccesses.filter(x => x.name.includes('weighted-parallel'));
  assert.equal(weighted.length, 2);
  assert.deepEqual(weighted[0].results, weighted[1].results);
  assert.deepEqual(weighted[0].results.paths.rows, [{hop_count: 1, total_cost: 1}]);
  const weightedProgram = JSON.parse(weighted[0].text);
  assert.deepEqual(weightedProgram.stages[0].steps[1].values.rows.map(x => x.edge_key), [11, 12, 10]);
  assert.equal(weightedProgram.stages[0].steps[3].shortest_path.weight, 'w');
  assert.ok(weighted[1].text.includes('WHERE hop_count > 0'));
});

test('Shortest packed profile includes external public transports and fresh-process rereads', async () => {
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  const corpus = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'graphShortestSourceSuccesses'],
    ['refusals', 'graphShortestSourceRefusals']]) {
    assert.ok(corpus.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(driver.includes("['scripts/fixtures/graph-shortest-source-input.mjs', 'graph-shortest-source-input.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_GRAPH_SHORTEST_ONLY = '1'"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_GRAPH_TRAVERSE_ONLY = '1'"));
  assert.ok(corpus.includes("process.env.ACTQL_TEST_GRAPH_SHORTEST_ONLY === '1'"));
  const start = driver.indexOf('const narrowPublicQuery =');
  const end = driver.indexOf('.includes(flag));', start);
  assert.ok(driver.slice(start, end).includes("'--graph-shortest-only'"));
  assert.match(driver, /if \(process\.argv\.includes\('--graph-graft-only'\)[^]*?process\.argv\.includes\('--graph-shortest-only'\)\) \{[^]*?exerciseRetainedQueryRestart\(\{ACTQL_TEST_RETAINED_COHORT_ONLY: '1'\}\)/u);
});
