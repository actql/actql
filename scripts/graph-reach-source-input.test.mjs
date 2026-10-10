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
  assert.equal(all.length, 13);
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
  const restart = driver.match(/if \((process\.argv\.includes\('--graph-graft-only'\)[^]*?)\) \{\s*\/\/ The Local and HTTPS producers have exited\.[^]*?exerciseRetainedQueryRestart\(\{ACTQL_TEST_RETAINED_COHORT_ONLY: '1'\}\)/u)?.[1];
  assert.ok(restart, 'the retained cohort reader must run after the producers exit');
  for (const family of ['graft', 'reach', 'shortest', 'mean']) {
    assert.ok(restart.includes(`process.argv.includes('--graph-${family}-only')`));
  }
});

test('Reach connected expectations distinguish direction, minimum depth and edge multiplicity', () => {
  const samples = graphReachSourceSuccesses.filter(sample => sample.name.includes('-connected-'));
  assert.equal(samples.length, 4);
  const out = samples.find(sample => sample.name === 'graph-reach-json-connected-out');
  const input = JSON.parse(out.text);
  assert.deepEqual(input.stages[0].steps[1].values.rows.map(row => [row.src, row.dst]),
    [[2, 3], [1, 1], [1, 2], [1, 2]]);
  assert.deepEqual(out.results.reached.rows.map(row => [row.node_id.$json.key[0], row.depth]),
    [[1, 0], [2, 1], [3, 2]]);
  const incoming = samples.find(sample => sample.name === 'graph-reach-json-connected-in');
  assert.deepEqual(incoming.results.reached.rows, [out.results.reached.rows[0]]);
  for (const direction of ['out', 'in']) {
    const machine = samples.find(sample => sample.name === 'graph-reach-json-connected-' + direction);
    const source = samples.find(sample => sample.name === 'graph-reach-aql-connected-' + direction);
    assert.deepEqual(source.results.reached.rows, machine.results.reached.rows.map(({depth}) => ({depth})));
    assert.ok(source.text.includes('LABEL Node PROPERTIES (seed)'));
    assert.ok(source.text.includes("where: 'seed = 1'"));
  }
});
