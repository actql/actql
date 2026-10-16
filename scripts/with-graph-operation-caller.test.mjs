import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {graphTraverseSourceSuccesses, graphTraverseSourceRefusals} from './fixtures/graph-traverse-source-input.mjs';
import {graphShortestSourceSuccesses, graphShortestSourceRefusals} from './fixtures/graph-shortest-source-input.mjs';
import {graphDiagnosticSourceSuccesses, graphDiagnosticSourceRefusals, graphDiagnosticSourceExecutionFailures} from './fixtures/graph-diagnostics-source-input.mjs';

const historical = JSON.parse(readFileSync(new URL('../reviews/2026-10-11-with-carrier-cutover/pre-with-graph-operation-source-input.json', import.meta.url), 'utf8'));
// Preserve original values, contracts, domains, bounds and I/O counts. The
// adopted degree contract renames its identity column, without changing cells.
function currentDegreeObligations(original) {
  const value = structuredClone(original);
  const output = value.results?.diagnostics;
  if (output?.columns.some(column => column.name === 'node')) {
    output.columns = output.columns.map(column => column.name === 'node'
      ? {...column, name: 'node_id'} : column);
    output.rows = output.rows.map(({node, ...row}) => ({...row, node_id: node}));
  }
  return value;
}

test('WITH Graph operation callers preserve all independent public obligations', () => {
  for (const [family, groups] of [
    ['traverse', {successes: graphTraverseSourceSuccesses, refusals: graphTraverseSourceRefusals}],
    ['shortest', {successes: graphShortestSourceSuccesses, refusals: graphShortestSourceRefusals}],
    ['diagnostics', {successes: graphDiagnosticSourceSuccesses, refusals: graphDiagnosticSourceRefusals, failures: graphDiagnosticSourceExecutionFailures}],
  ]) for (const [kind, current] of Object.entries(groups)) {
    const original = historical.groups[family][kind];
    const retained = current.filter(input => input.name !== 'graph-diagnostics-legacy-degree-column');
    assert.equal(retained.length, original.length);
    for (const input of retained) {
      const previous = original.find(item => item.name === input.name);
      assert.ok(previous, input.name);
      const {text: oldText, ...oldObligations} = previous;
      const {text, ...obligations} = input;
      assert.deepEqual(obligations, currentDegreeObligations(oldObligations), input.name);
      if (input.name === 'graph-diagnostics-json-degree') {
        const expected = JSON.parse(oldText);
        expected.stages[0].steps[3].select = ['degree', 'node_id'];
        expected.stages[0].results.rows.fields = ['degree', 'node_id'];
        assert.deepEqual(JSON.parse(text), expected);
      } else if (input.format === 'json') assert.equal(text, oldText, input.name);
      else {
        assert.notEqual(text, oldText, input.name);
        assert.ok(text.startsWith('WITH '), input.name);
        assert.ok(!/\bDATA\b|PROPERTY GRAPH/.test(text), input.name);
      }
    }
  }
});

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
