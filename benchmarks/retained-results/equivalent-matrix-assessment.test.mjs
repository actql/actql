import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {retainedMatrix} from './fixtures.mjs';
import {assessEquivalentMatrix, formatEquivalentMatrix} from
  './equivalent-matrix-assessment.mjs';

const revision = 'a'.repeat(40);
const equivalent = 'direct-duckdb-with-identical-obligations-and-independent-holding';
const digest = value => createHash('sha256').update(value).digest('hex');
const registrationSha256 = digest(readFileSync(new URL('experiment.json', import.meta.url)));

function record(fixture) {
  const provenance = {
    revision,
    sourceContentSha256: 'b'.repeat(64),
    releaseArtifactSha256: 'd'.repeat(64),
    runtime: 'v22.23.2',
    registrationSha256,
    programSha256: digest(JSON.stringify(fixture.program())),
    sourceDefinitionSha256: digest(fixture.createSourceSql),
  };
  return {
    caseId: fixture.id,
    pairs: Array.from({length: 7}, (_, index) => ({
      index,
      caseId: fixture.id,
      status: 'diagnostic-completed',
      acceptanceEligible: true,
      provenance: {...provenance},
      equivalentObligationAdmission: {accepted: true},
      transferWorkComparison: {terminalReleaseConfirmed: true},
      logicalAccountingEquivalent: true,
      acquisitionMetadataEquivalent: true,
      transferWorkAccountingEquivalent: true,
      order: index % 2
        ? ['retained-actql', equivalent] : [equivalent, 'retained-actql'],
      samples: {
        [equivalent]: {status: 'diagnostic-completed',
          warmMs: 100, coldMs: 200, executionMs: 100, cleanupMs: 1},
        'retained-actql': {status: 'completed', acceptanceEligible: true,
          warmMs: 105, coldMs: 250, executionMs: 120, cleanupMs: 1},
      },
    })),
  };
}

test('the equivalent comparison covers exactly all 27 registered cases', () => {
  const cases = retainedMatrix().map(record);
  const assessed = assessEquivalentMatrix(cases, revision);
  assert.equal(assessed.registeredCases, 27);
  assert.equal(assessed.status, 'pass');
  assert.equal(assessed.wholeExperimentAcceptance, false);
  assert.equal(assessed.cases.length, 27);
  assert.match(formatEquivalentMatrix(assessed), /one comparator/);
});

test('missing, duplicate and foreign cases remain visible and incomplete', () => {
  const [fixture] = retainedMatrix();
  const single = record(fixture);
  const missing = assessEquivalentMatrix([single], revision);
  assert.equal(missing.status, 'incomplete');
  assert.equal(missing.cases.filter(value => value.status === 'incomplete').length, 26);
  assert.match(formatEquivalentMatrix(missing), /missing-or-invalid-pairs/);
  const extra = assessEquivalentMatrix([single, single,
    {caseId: 'not-registered', pairs: []}], revision);
  assert.equal(extra.status, 'incomplete');
  assert.deepEqual(extra.duplicated, [fixture.id]);
  assert.deepEqual(extra.unexpected, ['not-registered']);
});

test('one-case provenance and release mutations cannot be aggregated as pass', () => {
  const [fixture] = retainedMatrix();
  const mutations = [
    value => { value.pairs.pop(); },
    value => { value.pairs[0].provenance.revision = 'c'.repeat(40); },
    value => { value.pairs[0].provenance.programSha256 = 'c'.repeat(64); },
    value => { value.pairs[0].samples['retained-actql'].cleanupMs = undefined; },
    value => { value.pairs[0].transferWorkComparison.terminalReleaseConfirmed = false; },
  ];
  for (const mutate of mutations) {
    const value = record(fixture);
    mutate(value);
    assert.equal(assessEquivalentMatrix([value], revision).cases[0].status,
      'incomplete');
  }
  const wrongRevision = record(fixture);
  for (const pair of wrongRevision.pairs) pair.provenance.revision = 'c'.repeat(40);
  assert.equal(assessEquivalentMatrix([wrongRevision], revision).cases[0].reason,
    'mixed-or-unexpected-revision');
});

test('a 27-case verdict requires one generated release build', () => {
  const cases = retainedMatrix().map(record);
  for (const pair of cases[1].pairs) {
    pair.provenance.releaseArtifactSha256 = 'e'.repeat(64);
  }
  const assessed = assessEquivalentMatrix(cases, revision);
  assert.equal(assessed.status, 'incomplete');
  assert.equal(assessed.cases[1].reason, 'mixed-release-build');
  assert.equal(assessed.cases.length, 27);
});
