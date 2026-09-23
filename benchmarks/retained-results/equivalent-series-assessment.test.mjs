import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {retainedCase} from './fixtures.mjs';
import {assessEquivalentSeries} from './equivalent-series-assessment.mjs';

const fixture = retainedCase('native-acquisition-full-validation-low-selectivity', 'narrow', 100);
const digest = value => createHash('sha256').update(value).digest('hex');
const equivalent = 'direct-duckdb-with-identical-obligations-and-independent-holding';

function admittedPairs() {
  const provenance = {
    revision: 'a'.repeat(40), sourceContentSha256: 'b'.repeat(64), runtime: 'v22.23.2',
    registrationSha256: digest(readFileSync(new URL('experiment.json', import.meta.url))),
    programSha256: digest(JSON.stringify(fixture.program())),
    sourceDefinitionSha256: digest(fixture.createSourceSql),
  };
  return Array.from({length: 7}, (_, index) => ({
    index, caseId: fixture.id, status: 'diagnostic-completed',
    acceptanceEligible: true, provenance: {...provenance},
    equivalentObligationAdmission: {accepted: true},
    transferWorkComparison: {terminalReleaseConfirmed: true},
    logicalAccountingEquivalent: true, acquisitionMetadataEquivalent: true,
    transferWorkAccountingEquivalent: true,
    order: index % 2 ? ['retained-actql', equivalent] : [equivalent, 'retained-actql'],
    samples: {
      [equivalent]: {status: 'diagnostic-completed', warmMs: 10,
        coldMs: 100, executionMs: 100, cleanupMs: 1},
      'retained-actql': {status: 'completed', acceptanceEligible: true,
        warmMs: 12, coldMs: 120, executionMs: 110, cleanupMs: 1},
    },
  }));
}

test('one comparator assessment uses registered warm and cold limits', () => {
  const result = assessEquivalentSeries(fixture, admittedPairs());
  assert.equal(result.scope, 'one-equivalent-comparator-only');
  assert.equal(result.status, 'pass');
  assert.deepEqual(result.gates.map(gate => gate.threshold), [10, 100]);
  const failing = admittedPairs();
  for (const pair of failing) pair.samples['retained-actql'].warmMs = 30;
  assert.equal(assessEquivalentSeries(fixture, failing).status, 'fail');
});

test('missing, changed, unqualified and unreleased evidence never passes', () => {
  const mutations = [
    pairs => pairs.pop(),
    pairs => { pairs[3].provenance.revision = 'c'.repeat(40); },
    pairs => { pairs[3].provenance.programSha256 = 'c'.repeat(64); },
    pairs => { pairs[3].provenance.sourceContentSha256 = 'c'.repeat(64); },
    pairs => { pairs[3].equivalentObligationAdmission.accepted = false; },
    pairs => { pairs[3].samples['retained-actql'].acceptanceEligible = false; },
    pairs => { pairs[3].samples['retained-actql'].cleanupMs = undefined; },
    pairs => { pairs[3].transferWorkComparison.terminalReleaseConfirmed = false; },
    pairs => { pairs[3].index = 4; },
  ];
  for (const mutate of mutations) {
    const pairs = admittedPairs();
    mutate(pairs);
    assert.equal(assessEquivalentSeries(fixture, pairs).status, 'incomplete');
  }
  const altered = {...fixture, limits: {...fixture.limits, sourceRows: 101}};
  assert.equal(assessEquivalentSeries(altered, admittedPairs()).status, 'incomplete');
});

test('large cases use the registered equivalent-obligations ratio', () => {
  const large = retainedCase('native-acquisition-full-validation-low-selectivity', 'narrow', 10000);
  const pairs = admittedPairs();
  const registrationSha256 = digest(readFileSync(new URL('experiment.json', import.meta.url)));
  for (const pair of pairs) {
    pair.caseId = large.id;
    pair.provenance = {...pair.provenance, registrationSha256,
      programSha256: digest(JSON.stringify(large.program())),
      sourceDefinitionSha256: digest(large.createSourceSql)};
    pair.samples['retained-actql'].executionMs = 130;
  }
  const result = assessEquivalentSeries(large, pairs);
  assert.equal(result.status, 'fail');
  assert.equal(result.gates[0].threshold, 1.25);
});
