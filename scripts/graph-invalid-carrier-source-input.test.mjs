import assert from 'node:assert/strict';
import test from 'node:test';
import {graphSubtractionSourceRefusals} from './fixtures/graph-subtraction-source-input.mjs';
import {graphUnionSourceRefusals} from './fixtures/graph-union-source-input.mjs';
import {graphMatchSourceRefusals} from './fixtures/graph-match-source-input.mjs';

test('known Relation inputs to Graph operations require exact invalid-input refusal', () => {
  for (const [items, name, source] of [
    [graphSubtractionSourceRefusals, 'graph-subtraction-lost-graph-scope',
      'FROM g |> node_rows() |> subtract_graphs(with: g)'],
    [graphUnionSourceRefusals, 'graph-union-refuse-7',
      'FROM g |> node_rows() |> union_graphs(with: g)'],
    [graphMatchSourceRefusals, 'graph-match-invalid-relation-is-not-graph',
      'FROM n |> match_nodes('],
  ]) {
    const item = items.find(item => item.name === name);
    assert.ok(item, name);
    assert.equal(item.expectedCode, 'ClientProgramInvalidInput', name);
    assert.ok(item.text.includes(source), name + ': preserve the invalid Carrier input');
  }
});
