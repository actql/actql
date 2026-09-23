import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {retainedCase, workloads} from './fixtures.mjs';
import {admitRetainedEstimateProfile} from './estimate-profile.mjs';

const sha256 = value => createHash('sha256').update(value).digest('hex');
const trainingFixture = retainedCase(workloads[0], 'narrow', 100);
const targetFixture = retainedCase(workloads[0], 'narrow', 1000);
const revision = 'a'.repeat(40);
const sourceHash = 'b'.repeat(64);
const targetSourceHash = 'c'.repeat(64);

function example() {
  const observations = [];
  for (let round = 0; round < 3; round++) {
    for (const candidate of round % 2 === 0
      ? ['local', 'duckdb'] : ['duckdb', 'local']) {
      observations.push({round, candidate, caseId: trainingFixture.id,
        outputCid: trainingFixture.identity().rowsCid,
        releaseConfirmed: true, cleanupMs: 1,
        taskElapsedMilliseconds: candidate === 'local' ? [12, 3, 4] : [18, 9, 8],
        taskRealizations: Array(3).fill(candidate)});
    }
  }
  const training = {version: 'actql-retained-calibration/0.1', revision,
    caseId: trainingFixture.id, sourceSha256: sourceHash,
    sourceDefinitionSha256: sha256(trainingFixture.createSourceSql),
    programSha256: sha256(JSON.stringify(trainingFixture.program())),
    expectedRowsCid: trainingFixture.identity().rowsCid,
    acceptanceEligible: false, observations};
  const trainingBytes = JSON.stringify(training);
  const profile = {version: 'actql-retained-estimate-profile/0.1', revision,
    trainingCaseId: trainingFixture.id, targetCaseId: targetFixture.id,
    trainingSha256: sha256(trainingBytes),
    trainingSourceSha256: sourceHash, targetSourceSha256: targetSourceHash,
    trainingSourceDefinitionSha256: training.sourceDefinitionSha256,
    targetSourceDefinitionSha256: sha256(targetFixture.createSourceSql),
    trainingProgramSha256: training.programSha256,
    targetProgramSha256: sha256(JSON.stringify(targetFixture.program())),
    localTaskMilliseconds: ['12', '3', '4'],
    nativeTaskMilliseconds: ['18', '9', '8'],
    acceptanceEligible: false};
  return {profile, trainingBytes, trainingFixture, targetFixture, revision,
    targetSourceSha256: targetSourceHash};
}

test('measured rates bind distinct registered training and evaluation cases', () => {
  const admitted = admitRetainedEstimateProfile(example());
  assert.deepEqual(admitted.localTaskMilliseconds, ['12', '3', '4']);
  assert.equal(admitted.targetCaseId, targetFixture.id);
});

test('case, source, revision and observation changes cannot reuse training rates', () => {
  for (const change of [
    input => { input.targetFixture = input.trainingFixture; },
    input => { input.targetSourceSha256 = 'd'.repeat(64); },
    input => { input.revision = 'e'.repeat(40); },
    input => { input.profile.localTaskMilliseconds[0] = '1'; },
    input => { input.profile.targetCaseId = trainingFixture.id; },
    input => { input.trainingBytes = input.trainingBytes.replace('"releaseConfirmed":true',
      '"releaseConfirmed":false'); },
    input => { input.trainingBytes = input.trainingBytes.replace('"candidate":"local"',
      '"candidate":"duckdb"'); },
  ]) {
    const input = example();
    change(input);
    assert.throws(() => admitRetainedEstimateProfile(input));
  }
});
