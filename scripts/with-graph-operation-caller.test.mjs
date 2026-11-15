import assert from 'node:assert/strict';
import test from 'node:test';
import {graphDiagnosticSourceSuccesses, graphDiagnosticSourceRefusals} from './fixtures/graph-diagnostics-source-input.mjs';

test('degree public fixtures expose only the adopted node_id column', () => {
  const successes = graphDiagnosticSourceSuccesses.filter(input =>
    input.results.diagnostics.columns.some(column => column.name === 'degree'));
  assert.equal(successes.length, 5);
  for (const input of successes) {
    assert.deepEqual(input.results.diagnostics.columns, [
      {name: 'degree', contract: {type: 'number', nullable: false}},
      {name: 'node_id', contract: {type: 'json', nullable: false}},
    ]);
    for (const row of input.results.diagnostics.rows) {
      assert.deepEqual(Object.keys(row).sort(), ['degree', 'node_id']);
    }
  }
  const refusal = graphDiagnosticSourceRefusals.filter(input =>
    input.name === 'graph-diagnostics-legacy-degree-column');
  assert.equal(refusal.length, 1);
  assert.ok(refusal[0].text.endsWith('degree(direction: "both") |> SELECT node |> RESULT diagnostics'));
});
