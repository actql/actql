import assert from 'node:assert/strict';
import {sequenceSourceSuccesses, sequenceSourceRefusals}
  from './fixtures/sequence-source-input.mjs';

// Complete original F05 inventory, not an easier installed-product subset.
export const releaseSequenceSuccessNames = Object.freeze([
  'relation', 'events', 'nullable-case', 'gap-adjacent', 'gap-subsequence', 'parameters',
].flatMap(name => ['json', 'sql', 'aql-text'].map(format => `sequence-${format}-${name}`)));
export const releaseSequenceRefusalNames = Object.freeze([
  'string-predicate', 'prior-label-input', 'duplicate-label', 'reserved-label',
  'nonboolean-predicate', 'zero-within', 'zero-output-guard', 'implicit-overlap',
  'json-predicate-adapter',
].map(name => `sequence-${name}`));

// Preserve the original source, Expression AST, parameters, rows and schema by
// identity. Selection does not lower, evaluate or rewrite any submitted input.
export function selectReleaseSequenceQueryCases({
  successes = sequenceSourceSuccesses,
  refusals = sequenceSourceRefusals,
} = {}) {
  assert.deepEqual(successes.map(value => value.name), releaseSequenceSuccessNames,
    'The complete Sequence normal inventory must remain exact and ordered');
  assert.deepEqual(refusals.map(value => value.name), releaseSequenceRefusalNames,
    'The complete Sequence refusal inventory must remain exact and ordered');
  for (const value of successes) {
    assert.equal(value.sourceReadCount, 0, `Source-backed Sequence case: ${value.name}`);
    assert.equal(value.sourceReadSessionCount, 0, `Source session required: ${value.name}`);
    assert.ok(Array.isArray(value.results?.answer?.rows));
    assert.ok(Array.isArray(value.results?.answer?.columns));
  }
  return Object.freeze({successes: Object.freeze([...successes]),
    refusals: Object.freeze([...refusals])});
}
