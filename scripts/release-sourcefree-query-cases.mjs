import assert from 'node:assert/strict';
import {inUnnestLiteralArraySuccesses, inUnnestLiteralArrayRefusals}
  from './fixtures/in-unnest-literal-array-source-input.mjs';

export const releaseSourcefreeSuccessNames = Object.freeze([
  'general-element', 'array-field', 'conditional-array', 'lazy-array-branch',
].map(name => `in-unnest-literal-array-${name}`));
export const releaseSourcefreeRefusalNames = Object.freeze([
  'annotation-not-erased', 'mixed-types', 'undeclared',
  'wrong-parameter-value', 'nonfinite', 'negative-zero',
].map(name => `in-unnest-literal-array-${name}`));

// Selection preserves the authored rows, ordered schema and parameters by
// identity. It neither evaluates source nor changes the development harness.
export function selectReleaseSourcefreeQueryCases({
  successes = inUnnestLiteralArraySuccesses,
  refusals = inUnnestLiteralArrayRefusals,
} = {}) {
  const selected = releaseSourcefreeSuccessNames.map(name => {
    const matches = successes.filter(value => value.name === name);
    assert.equal(matches.length, 1, `Missing or duplicate release case: ${name}`);
    const value = matches[0];
    assert.equal(value.sourceReadCount, 0, `Source-backed release case: ${name}`);
    assert.equal(value.sourceReadSessionCount, 0, `Source session required: ${name}`);
    assert.ok(Array.isArray(value.expected) && Array.isArray(value.columns));
    return value;
  });
  assert.deepEqual(refusals.map(value => value.name), releaseSourcefreeRefusalNames,
    'The release refusal inventory must remain exact and ordered');
  return Object.freeze({successes: Object.freeze(selected),
    refusals: Object.freeze([...refusals])});
}
