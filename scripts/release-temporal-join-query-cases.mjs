import assert from 'node:assert/strict';
import {temporalJoinSourceSuccesses, temporalJoinSourceRefusals}
  from './fixtures/temporal-join-source-input.mjs';

const normalNames = ['asof-left', 'asof-inner', 'interval-left', 'interval-inner']
  .flatMap(name => ['json', 'sql', 'aql-text'].map(format => `temporal-${format}-${name}`));
const refusalNames = ['asof-zero-tolerance', 'wrong-left-receiver', 'wrong-right-receiver',
  'string-producer', 'missing-output', 'reserved-output', 'interval-full',
  'interval-zero-bound', 'unknown-right-field'].map(name => `temporal-${name}`);

// Preserve the existing JSON controls and source fixtures without evaluation.
export function selectReleaseTemporalJoinQueryCases({successes = temporalJoinSourceSuccesses,
  refusals = temporalJoinSourceRefusals} = {}) {
  assert.deepEqual(successes.map(item => item.name), normalNames);
  assert.deepEqual(refusals.map(item => item.name), refusalNames);
  for (const item of successes) {
    const resultName = item.format === 'json' ? 'answer' : 'main';
    assert.equal(item.sourceReadCount, 0);
    // The original fixture omits this optional observation field. Do not add
    // it to the authored request or silently accept a Source-backed case.
    assert.ok(item.sourceReadSessionCount === undefined || item.sourceReadSessionCount === 0);
    assert.ok(Array.isArray(item.results[resultName].rows));
    assert.ok(Array.isArray(item.results[resultName].columns));
  }
  return Object.freeze({successes: Object.freeze([...successes]), refusals: Object.freeze([...refusals])});
}
