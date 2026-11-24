import assert from 'node:assert/strict';
import {carrierPeerSuccesses, carrierPeerRefusals}
  from './fixtures/carrier-peer-scope-public-input.mjs';
export function selectReleaseCarrierPeerCases({successes = carrierPeerSuccesses,
  refusals = carrierPeerRefusals} = {}) {
  assert.deepEqual(successes.map(item => item.name), ['carrier-peer-json-cosine',
    ...['flat', 'intermediate-with', 'nested-candidate', 'shared-query', 'cosine']
      .flatMap(name => ['sql', 'aql-text'].map(format => `carrier-peer-${name}-${format}`))]);
  assert.deepEqual(refusals.map(item => item.name),
    ['sql', 'aql-text'].map(format => `carrier-peer-wrong-shadow-${format}`));
  assert.equal(successes.reduce((n, item) => n + item.sourceReadSessionCount, 0), 18);
  for (const item of successes) {
    assert.ok(Array.isArray(item.results.answer.rows) && Array.isArray(item.results.answer.columns));
  }
  return {successes, refusals};
}
