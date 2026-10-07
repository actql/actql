import test from 'node:test';
import assert from 'node:assert/strict';
import {getCheckReasonCatalogInfo, getCheckReasonCatalogEntry, explainCheckReason} from './index.mjs';
// Independent fixed migration pins: not generated from this catalog.
const reasonCid = 'sha256:672a0158dfe91c7525eb7d02efbcf80b0094a05ecfa2b42fe08df945dd26fa53';
test('public check catalog exposes separate readonly presentation metadata without authority', () => {
  assert.deepEqual(getCheckReasonCatalogInfo(), {version: 'actql-check-reason-catalog/0.1',
    revision: '2026-10-07.2', reasonSchemaCid: reasonCid});
  const entry = getCheckReasonCatalogEntry('parameter_value_required');
  assert.equal(entry.family, 'requirement');
  assert.equal(entry.default_severity, 'info');
  assert.equal(entry.facts_schema, '#/reason_schema');
  assert.ok(Object.isFrozen(entry.presentation.variants));
  assert.throws(() => {entry.default_severity = 'error';}, TypeError);
  assert.equal(Object.hasOwn(entry, 'verified'), false);
  assert.equal(Object.hasOwn(entry, 'next'), false);
  for (const code of ['future_reason', 'constructor', '__proto__', null, {}]) {
    assert.equal(getCheckReasonCatalogEntry(code), undefined);
  }
});
test('catalog selection preserves specific safe advice and unknown fallbacks', () => {
  assert.deepEqual(explainCheckReason({code: 'implementation_limit', facts: {issue: 'function_lowering_unresolved'}}),
    {kind: 'known', summary: 'The expression lowerer cannot classify or support this function form.',
      hint: 'Ask the checking-context owner to review function support at the original expression; this is not a proven function-name violation.'});
  assert.equal(explainCheckReason({code: 'binding_json_invalid', facts: {document: 'private', issue: 'invalid_number'}}).kind, 'unknown');
  assert.equal(explainCheckReason({code: 'graph_operation_invalid', facts: {operation: 'subgraph', issue: 'invalid_kind'}}).kind, 'unknown');
  assert.equal(explainCheckReason({code: 'operation_parameter_invalid', facts: {domain: 'signed_milliseconds'}}).hint,
    'Supply integer milliseconds from -9007199254740991 through 9007199254740991 without negative zero, or a positive duration string.');
  assert.deepEqual(explainCheckReason({code: 'future_reason', facts: {private: 'hidden'}}),
    {kind: 'unknown', summary: 'No supported explanation is available for this reason.'});
});
