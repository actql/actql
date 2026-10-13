import assert from 'node:assert/strict';
import {carrierContinuationSuccesses, carrierContinuationRefusals}
  from './fixtures/carrier-continuation-source-input.mjs';

const number = {type: 'number', nullable: false};
export const carrierContinuationRecordsSchema = Object.freeze({id: Object.freeze(number),
  amount: Object.freeze({type: 'number', nullable: true})});
// A trusted fixture owns this complete original extent. Do not derive facts
// from Runtime observations, filter rows here or replace the independent data.
export const carrierContinuationRecordsRows = Object.freeze(
  carrierContinuationSuccesses.find(item => item.sourceReadSessionCount === 1)
    .sourceRows.map(row => Object.freeze({...row})));

export function selectReleaseCarrierContinuationCases() {
  const names = ['graph-marked', 'graph-unmarked', 'events-flat', 'events-with',
    'source-events-flat', 'source-events-with'].flatMap(name => ['sql', 'aql-text']
    .map(format => `carrier-continuation-${name}-${format}`));
  assert.deepEqual(carrierContinuationSuccesses.map(item => item.name),
    ['carrier-continuation-json-events-control', ...names]);
  const bad = ['demanded-events', 'unused-events', 'root-events', 'marked-relation',
    'shadowed-events', 'relation-tail-graph-call', 'key-property-collision']
    .flatMap(name => ['sql', 'aql-text'].map(format => `carrier-continuation-refusal-${name}-${format}`));
  assert.deepEqual(carrierContinuationRefusals.map(item => item.name),
    [...bad, 'carrier-continuation-refusal-key-property-collision-json']);
  for (const item of carrierContinuationSuccesses) {
    assert.ok([0, 1].includes(item.sourceReadSessionCount));
    if (item.sourceReadSessionCount === 1) assert.deepEqual(item.sourceRows, carrierContinuationRecordsRows);
    else assert.equal(item.sourceReadCount, 0);
  }
  return {successes: carrierContinuationSuccesses, refusals: carrierContinuationRefusals};
}
