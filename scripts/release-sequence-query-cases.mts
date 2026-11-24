import assert from 'node:assert/strict';
import {sequenceSourceSuccesses, sequenceSourceRefusals}
  from './fixtures/sequence-source-input.mjs';

// Complete current inventory: original explicit F05 inputs, the formerly
// refused overlap omission, and the adopted v0.1 all-omitted forms.
export const releaseSequenceSuccessNames = Object.freeze([
 ...[
  'relation', 'events', 'nullable-case', 'gap-adjacent', 'gap-subsequence', 'parameters',
 ].flatMap(name => ['json', 'sql', 'aql-text'].map(format => `sequence-${format}-${name}`)),
 'sequence-implicit-overlap',
 ...['json','sql','aql-text'].map(format=>`sequence-${format}-omitted-defaults`),
]);
export const releaseSequenceRefusalNames = Object.freeze([
  'string-predicate', 'prior-label-input', 'duplicate-label', 'reserved-label',
  'nonboolean-predicate', 'zero-within', 'zero-output-guard', 'invalid-overlap',
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
    const resultName = value.format === 'json' ? 'answer' : 'main';
    assert.equal(value.sourceReadCount, 0, `Source-backed Sequence case: ${value.name}`);
    assert.equal(value.sourceReadSessionCount, 0, `Source session required: ${value.name}`);
    assert.ok(Array.isArray(value.results?.[resultName]?.rows));
    assert.ok(Array.isArray(value.results?.[resultName]?.columns));
  }
  return Object.freeze({successes: Object.freeze([...successes]),
    refusals: Object.freeze([...refusals])});
}
