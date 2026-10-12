import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {graphMeanProgram, graphMeanSourceOracles, graphMeanSourceRefusalOracles}
  from './fixtures/graph-mean-source-input.mjs';

test('Mean independent oracle preserves explicit sample occurrences and nullable numeric output', () => {
  const step = graphMeanProgram.stages[0].steps[3];
  assert.equal(Object.hasOwn(step, 'from'), false);
  assert.deepEqual(step.mean_graphs.with, ['g', 'g', 'g']);
  assert.deepEqual(step.mean_graphs.weights, [1, 2, 0]);
  const sample = graphMeanSourceOracles[0];
  assert.deepEqual(Object.keys(sample.results).sort(), ['edges', 'nodes']);
  assert.deepEqual(sample.results.nodes.rows,
    [{p: 7, part: 7, node_key: 1, labels: ['Person']}]);
  assert.deepEqual(sample.results.edges.rows.map(row => [row.edge_key, row.w]),
    [[10, 2], [11, 5]]);
  assert.deepEqual(sample.results.nodes.columns[0],
    {name: 'p', contract: {type: 'number', nullable: true}});
  assert.deepEqual(sample.results.edges.columns[0],
    {name: 'w', contract: {type: 'number', nullable: true}});
  const empty = JSON.parse(graphMeanSourceOracles[1].text);
  assert.deepEqual(empty.stages[0].steps.slice(0, 2).map(step => step.values.rows), [[], []]);
  assert.deepEqual(Object.values(graphMeanSourceOracles[1].results).map(value => value.rows), [[], []]);
});

test('Mean public acceptance reuses the existing fresh-process retained cohort reader', async () => {
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  const corpus = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_GRAPH_MEAN_ONLY = '1'"));
  assert.ok(corpus.includes('graphMeanOnly ? {successes: graphMeanSourceOracles, refusals: graphMeanSourceRefusals}'));
  assert.ok(corpus.includes('scopeInputs.successes.push(...graphMeanSourceOracles)'));
  assert.ok(corpus.includes('scopeInputs.refusals.push(...graphMeanSourceRefusals)'));
  const start = driver.indexOf("if (process.argv.includes('--graph-graft-only') ||");
  const end = driver.indexOf('return;', start);
  assert.ok(driver.slice(start, end).includes("process.argv.includes('--graph-mean-only')"));
  assert.ok(driver.slice(start, end).includes("exerciseRetainedQueryRestart({ACTQL_TEST_RETAINED_COHORT_ONLY: '1'})"));
});

test('Mean AQL oracle uses a generator, not a Pipe left operand or implicit current input', () => {
  const aql = graphMeanSourceOracles.filter(sample => sample.name.startsWith('graph-mean-aql-generator-'));
  assert.equal(aql.length, 2);
  for (const sample of aql) {
    assert.match(sample.text, /combined AS \(mean_graphs\(with: \[g, g, g\], weights: \[1, 2, 0\]/u);
    assert.equal(sample.text.includes('FROM g |> mean_graphs'), false);
    assert.match(sample.text, /FROM combined \|> (node_rows|edge_rows)\(\)/u);
  }
  assert.match(graphMeanSourceRefusalOracles[0], /FROM g \|> mean_graphs/u);
  assert.match(graphMeanSourceRefusalOracles[1], /weights: \[0, 0, 0\]/u);
  assert.match(graphMeanSourceRefusalOracles[2], /with: \[g, missing, g\]/u);
});

test('Mean asymmetric controls distinguish sample port order from producer order', () => {
  const samples = graphMeanSourceOracles.filter(sample => sample.name.includes('asymmetric-ordered'));
  assert.equal(samples.length, 2);
  const machine = samples.find(sample => sample.format === 'json');
  const steps = JSON.parse(machine.text).stages[0].steps;
  assert.equal(steps[2].as, 'g');
  assert.equal(steps[3].as, 'doubled');
  assert.deepEqual(steps[4].mean_graphs.with, ['doubled', 'g', 'doubled']);
  assert.deepEqual(steps[4].mean_graphs.weights, [1, 2, 0]);
  assert.deepEqual(machine.results.nodes.rows.map(row => row.p), [28 / 3]);
  assert.deepEqual(machine.results.edges.rows.map(row => [row.edge_key, row.w]),
    [[10, 8 / 3], [11, 20 / 3]]);
  const source = samples.find(sample => sample.format === 'aql-text');
  assert.match(source.text, /with: \[doubled, g, doubled\], weights: \[1, 2, 0\]/u);
  assert.deepEqual(source.results.edges, machine.results.edges);
  assert.notEqual(28 / 3, 35 / 3, 'swapping distinct positive samples changes the independent result');
});
