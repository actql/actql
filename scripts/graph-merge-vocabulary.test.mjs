import assert from 'node:assert/strict';
import test from 'node:test';
import {graphUnionSourceSuccesses, graphUnionSourceRefusals} from './fixtures/graph-union-source-input.mjs';
import {graphSubtractionSourceSuccesses, graphSubtractionSourceRefusals} from './fixtures/graph-subtraction-source-input.mjs';

test('typed merge spellings retain independent node and keyed parallel-edge results', () => {
  for (const [prefix, cases, p, w] of [
    ['graph-union', graphUnionSourceSuccesses, 21, [6, 15]],
    ['graph-subtraction', graphSubtractionSourceSuccesses, 14, [4, 10]],
  ]) {
    for (const spelling of ['uppercase', 'quoted']) {
      const nodes = cases.find(c => c.name === `${prefix}-${spelling}-merge-vocabulary-nodes`);
      const edges = cases.find(c => c.name === `${prefix}-${spelling}-merge-vocabulary-edges`);
      assert.deepEqual(nodes.results.nodes.rows, [{p, part: 7, node_key: 1, labels: ['Person']}]);
      assert.deepEqual(edges.results.edges.rows, [
        {w: w[0], part: 7, edge_key: 10, labels: ['R']},
        {w: w[1], part: 7, edge_key: 11, labels: ['R']},
      ]);
      assert.deepEqual(nodes.results.nodes.columns.map(c => c.name), ['p', 'part', 'node_key', 'labels']);
      assert.deepEqual(edges.results.edges.columns.map(c => c.name), ['w', 'part', 'edge_key', 'labels']);
      assert.equal(nodes.sourceReadCount, 0);
      assert.equal(edges.sourceReadCount, 0);
    }
  }
});

test('quoted merge vocabulary is distinguished from authored property-name selectors', () => {
  for (const cases of [graphUnionSourceSuccesses, graphSubtractionSourceSuccesses]) {
    const selected = cases.filter(c => c.name.includes('quoted-merge-vocabulary'));
    assert.equal(selected.length, 2);
    for (const c of selected) {
      assert.ok(c.text.includes("`Node_Properties`: {P: 'number_sum'}"));
      assert.ok(c.text.includes("`Edge_Properties`: {W: 'number_sum'}"));
    }
  }
});

test('folded duplicates and unmodified invalid strategies require typed input refusal', () => {
  for (const [prefix, cases] of [
    ['graph-union', graphUnionSourceRefusals],
    ['graph-subtraction', graphSubtractionSourceRefusals],
  ]) {
    for (const suffix of ['duplicate-node-policy', 'duplicate-edge-policy', 'strategy-value-is-not-vocabulary']) {
      const c = cases.find(c => c.name === `${prefix}-${suffix}`);
      assert.equal(c.expectedCode, 'ClientProgramInvalidInput');
      if (suffix === 'strategy-value-is-not-vocabulary') assert.ok(c.text.includes("p: 'NUMBER_SUM'"));
    }
  }
  for (const suffix of ['property-map-collision', 'unknown-merge-field']) {
    assert.equal(graphUnionSourceRefusals.find(c => c.name === 'graph-union-' + suffix).expectedCode,
      'ClientProgramInvalidInput');
  }
});

test('existing unsupported peer shapes retain the common implementation-limit category', () => {
  for (const index of [1, 5]) {
    assert.equal(graphUnionSourceRefusals.find(c => c.name === 'graph-union-refuse-' + index).expectedCode,
      'ClientProgramImplementationLimit');
  }
  for (const suffix of ['list-peer', 'empty-peer-list', 'missing-peer', 'extra-argument']) {
    assert.equal(graphSubtractionSourceRefusals.find(c => c.name === 'graph-subtraction-' + suffix).expectedCode,
      'ClientProgramImplementationLimit');
  }
  // A Relation at a Graph input is invalid before implementation selection.
  for (const [cases, name] of [
    [graphUnionSourceRefusals, 'graph-union-refuse-7'],
    [graphSubtractionSourceRefusals, 'graph-subtraction-lost-graph-scope'],
  ]) assert.equal(cases.find(c => c.name === name).expectedCode,
    'ClientProgramInvalidInput');
});
