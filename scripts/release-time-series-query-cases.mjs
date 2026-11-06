import assert from 'node:assert/strict';
import {timeSeriesPrimarySuccesses, timeSeriesPrimaryRefusals}
  from './fixtures/time-series-primary-source-input.mjs';
const normalNames = ['json', 'sql', 'text', 'bare-text', 'empty-json', 'empty-sql',
  'parameters-json', 'parameters-sql', 'parameters-aql-text'].map(name => `time-series-primary-${name}`);
const refusalNames = ['missing-step', 'extra-field', 'duplicate-field', 'unused-reversed',
  'unused-invalid-time', 'consuming-pipe', 'nullable-endpoint'].map(name => `time-series-primary-refusal-${name}`);
export function selectReleaseTimeSeriesQueryCases({successes = timeSeriesPrimarySuccesses,
  refusals = timeSeriesPrimaryRefusals} = {}) {
  assert.deepEqual(successes.map(item => item.name), normalNames);
  assert.deepEqual(refusals.map(item => item.name), refusalNames);
  for (const item of successes) {
    const resultName = item.format === 'json' ? 'answer' : 'main';
    assert.equal(item.sourceReadCount, 0);
    assert.equal(item.sourceReadSessionCount, 0);
    assert.ok(Array.isArray(item.results[resultName].rows));
    assert.ok(Array.isArray(item.results[resultName].columns));
  }
  return Object.freeze({successes: Object.freeze([...successes]), refusals: Object.freeze([...refusals])});
}
