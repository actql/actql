import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {graphReachSourceSuccesses, graphReachSourceRefusals}
  from './fixtures/graph-reach-source-input.mjs';

test('Reach public oracles retain independent depth zero, two consumers and empty schemas', () => {
  const machine = graphReachSourceSuccesses[0];
  const program = JSON.parse(machine.text);
  assert.deepEqual(Object.keys(program.results).sort(), ['a', 'b']);
  assert.deepEqual(machine.results.a, machine.results.b);
  assert.equal(machine.results.a.rows[0].depth, 0);
  const start = program.stages[0].steps[2].reach.start;
  assert.deepEqual(machine.results.a.rows[0].start_id, {$json: start});
  assert.deepEqual(machine.results.a.rows[0].node_id, {$json: start});
  for (const sample of graphReachSourceSuccesses.filter(x => x.name.includes('empty'))) {
    assert.deepEqual(sample.results.reached.rows, []);
    assert.deepEqual(sample.results.reached.columns.map(x => x.name), ['start_id', 'node_id', 'depth']);
  }
  const all = [...graphReachSourceSuccesses, ...graphReachSourceRefusals];
  assert.equal(all.length, 9);
  assert.equal(new Set(all.map(x => x.name)).size, all.length);
});

test('Reach narrow packed selection uses public transports and fresh-process retained reads', async () => {
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  const corpus = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'graphReachSourceSuccesses'], ['refusals', 'graphReachSourceRefusals']]) {
    assert.ok(corpus.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(corpus.includes("const graphReachOnly = process.env.ACTQL_TEST_GRAPH_REACH_ONLY === '1'"));
  assert.ok(corpus.includes('graphReachOnly\n    ? {successes: graphReachSourceSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_GRAPH_REACH_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/graph-reach-source-input.mjs', 'graph-reach-source-input.mjs']"));
  const narrow = driver.slice(driver.indexOf('const narrowPublicQuery ='), driver.indexOf('.includes(flag));'));
  assert.ok(narrow.includes("'--graph-reach-only'"));
  assert.match(driver, /if \(process\.argv\.includes\('--graph-graft-only'\) \|\| process\.argv\.includes\('--graph-reach-only'\)\) \{[^]*?exerciseRetainedQueryRestart\(\{ACTQL_TEST_RETAINED_COHORT_ONLY: '1'\}\)/u);
});
