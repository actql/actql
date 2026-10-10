import assert from 'node:assert/strict';
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

test('Mean AQL oracle uses a generator, not a Pipe left operand or implicit current input', () => {
  const aql = graphMeanSourceOracles.filter(sample => sample.format === 'aql-text');
  assert.equal(aql.length, 2);
  for (const sample of aql) {
    assert.match(sample.text, /DATA combined = mean_graphs\(with: \[g, g, g\], weights: \[1, 2, 0\]/u);
    assert.equal(sample.text.includes('FROM g |> mean_graphs'), false);
    assert.match(sample.text, /FROM combined \|> (node_rows|edge_rows)\(\)/u);
  }
  assert.match(graphMeanSourceRefusalOracles[0], /FROM g \|> mean_graphs/u);
  assert.match(graphMeanSourceRefusalOracles[1], /weights: \[0, 0, 0\]/u);
  assert.match(graphMeanSourceRefusalOracles[2], /with: \[g, missing, g\]/u);
});
