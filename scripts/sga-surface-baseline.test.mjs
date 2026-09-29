import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {structuralToJson, jsonAdmissionDiagnostic} from
  '../_build/js/debug/build/aql_text_test_bridge/aql_text_test_bridge.js';
const fixture = name => readFileSync(new URL(
  `../spec/frontend/fixtures/sga-surface/${name}`, import.meta.url), 'utf8');

test('existing Graph OP source preserves shared producers and explicit Results', () => {
  const expected = fixture('reach-subgraph.expected-program.json');
  assert.equal(jsonAdmissionDiagnostic(expected), '');
  assert.deepEqual(JSON.parse(structuralToJson(fixture('reach-subgraph.op.aql'))),
    JSON.parse(expected));
});
