// Admit measured candidate rates for a different registered evaluation case.
// This validates calibration provenance; timing and obligation acceptance are
// separate gates and must never be inferred from this result.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {workloads} from './fixtures.mjs';
import {registeredLocalEligibility} from './candidate-eligibility.mjs';

const sha256 = value => createHash('sha256').update(value).digest('hex');
const duration = value => Number.isFinite(value) && value >= 0;

export function admitRetainedEstimateProfile({profile, trainingBytes,
  trainingFixture, targetFixture, revision, targetSourceSha256}) {
  assert.equal(typeof trainingBytes, 'string', 'MissingTrainingBytes');
  assert.equal(typeof revision, 'string', 'MissingCalibrationRevision');
  assert.equal(typeof targetSourceSha256, 'string', 'MissingTargetSourceHash');
  const training = JSON.parse(trainingBytes);
  const taskCount = targetFixture?.workload === workloads[1] ? 4 : 3;
  assert(trainingFixture && targetFixture && trainingFixture.id !== targetFixture.id,
    'CalibrationTargetMustBeHeldOut');
  assert.equal(trainingFixture.workload, targetFixture.workload,
    'CalibrationWorkloadMismatch');
  assert.equal(trainingFixture.layout, targetFixture.layout,
    'CalibrationLayoutMismatch');
  assert.equal(profile?.version, 'actql-retained-estimate-profile/0.1');
  assert.equal(training?.version, 'actql-retained-calibration/0.1');
  assert.equal(profile.revision, revision);
  assert.equal(training.revision, revision);
  assert.equal(profile.trainingSha256, sha256(trainingBytes),
    'CalibrationTrainingHashMismatch');
  assert.equal(profile.trainingCaseId, trainingFixture.id);
  assert.equal(profile.targetCaseId, targetFixture.id);
  assert.equal(training.caseId, trainingFixture.id);
  assert.equal(profile.trainingSourceSha256, training.sourceSha256);
  assert.equal(profile.targetSourceSha256, targetSourceSha256);
  assert.equal(profile.trainingSourceDefinitionSha256,
    sha256(trainingFixture.createSourceSql));
  assert.equal(profile.targetSourceDefinitionSha256,
    sha256(targetFixture.createSourceSql));
  assert.equal(training.sourceDefinitionSha256,
    profile.trainingSourceDefinitionSha256);
  assert.equal(profile.trainingProgramSha256,
    sha256(JSON.stringify(trainingFixture.program())));
  assert.equal(profile.targetProgramSha256,
    sha256(JSON.stringify(targetFixture.program())));
  assert.equal(training.programSha256, profile.trainingProgramSha256);
  assert.equal(training.expectedRowsCid, trainingFixture.identity().rowsCid);
  const trainingEligibility = registeredLocalEligibility(trainingFixture);
  const targetEligibility = registeredLocalEligibility(targetFixture);
  assert.deepEqual(training.localEligibility, trainingEligibility);
  assert.deepEqual(profile.localEligibility, targetEligibility);
  assert.equal(trainingEligibility.eligible, targetEligibility.eligible,
    'CalibrationEligibilityMismatch');
  assert.equal(profile.acceptanceEligible, false);
  assert.equal(training.acceptanceEligible, false);
  assert.equal(Array.isArray(training.observations), true);
  assert.equal(training.observations.length,
    trainingEligibility.eligible ? 6 : 3, 'IncompleteCandidateTraining');
  const observations = training.observations;
  for (let round = 0; round < 3; round++) {
    const candidates = trainingEligibility.eligible
      ? round % 2 === 0 ? ['local', 'duckdb'] : ['duckdb', 'local']
      : ['duckdb'];
    for (const [position, candidate] of candidates.entries()) {
      const observation = observations[round * candidates.length + position];
      assert.equal(observation.round, round);
      assert.equal(observation.candidate, candidate);
      assert.equal(observation.caseId, trainingFixture.id);
      assert.equal(observation.outputCid, training.expectedRowsCid);
      assert.equal(observation.releaseConfirmed, true);
      assert(duration(observation.cleanupMs));
      assert.equal(observation.taskElapsedMilliseconds?.length, taskCount);
      assert(observation.taskElapsedMilliseconds.every(duration));
      assert.deepEqual(observation.taskRealizations,
        Array(taskCount).fill(candidate), 'CandidateTrainingWasNotForced');
    }
  }
  const median = values => [...values].sort((a, b) => a - b)[1];
  const rates = candidate => Array.from({length: taskCount}, (_, task) =>
    String(Math.max(1, Math.ceil(median(observations
      .filter(value => value.candidate === candidate)
      .map(value => value.taskElapsedMilliseconds[task]))))));
  assert.deepEqual(profile.localTaskMilliseconds,
    trainingEligibility.eligible ? rates('local') : null);
  assert.deepEqual(profile.nativeTaskMilliseconds, rates('duckdb'));
  return Object.freeze({
    localEligible: targetEligibility.eligible,
    localTaskMilliseconds: targetEligibility.eligible
      ? Object.freeze([...profile.localTaskMilliseconds]) : null,
    nativeTaskMilliseconds: Object.freeze([...profile.nativeTaskMilliseconds]),
    estimateSource: `sha256:${profile.trainingSha256}`,
    trainingCaseId: trainingFixture.id,
    targetCaseId: targetFixture.id,
    scope: 'held-out measured candidate rates; not timing acceptance',
  });
}
