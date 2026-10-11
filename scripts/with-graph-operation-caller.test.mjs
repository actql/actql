import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {graphTraverseSourceSuccesses, graphTraverseSourceRefusals} from './fixtures/graph-traverse-source-input.mjs';
import {graphShortestSourceSuccesses, graphShortestSourceRefusals} from './fixtures/graph-shortest-source-input.mjs';
import {graphDiagnosticSourceSuccesses, graphDiagnosticSourceRefusals, graphDiagnosticSourceExecutionFailures} from './fixtures/graph-diagnostics-source-input.mjs';

const historical = JSON.parse(readFileSync(new URL('../reviews/2026-10-11-with-carrier-cutover/pre-with-graph-operation-source-input.json', import.meta.url), 'utf8'));
// The original independently authored values, full ordered contracts, identity
// domains, bounds and I/O counts survive the source-language cutover unchanged.
test('WITH Graph operation callers preserve all independent public obligations', () => {
  for (const [family, groups] of [
    ['traverse', {successes: graphTraverseSourceSuccesses, refusals: graphTraverseSourceRefusals}],
    ['shortest', {successes: graphShortestSourceSuccesses, refusals: graphShortestSourceRefusals}],
    ['diagnostics', {successes: graphDiagnosticSourceSuccesses, refusals: graphDiagnosticSourceRefusals, failures: graphDiagnosticSourceExecutionFailures}],
  ]) for (const [kind, current] of Object.entries(groups)) {
    const original = historical.groups[family][kind];
    assert.equal(current.length, original.length);
    for (const input of current) {
      const previous = original.find(item => item.name === input.name);
      assert.ok(previous, input.name);
      const {text: oldText, ...oldObligations} = previous;
      const {text, ...obligations} = input;
      assert.deepEqual(obligations, oldObligations, input.name);
      if (input.format === 'json') assert.equal(text, oldText, input.name);
      else {
        assert.notEqual(text, oldText, input.name);
        assert.ok(text.startsWith('WITH '), input.name);
        assert.ok(!/\bDATA\b|PROPERTY GRAPH/.test(text), input.name);
      }
    }
  }
});
