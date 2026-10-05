// Admit a Native-only measured selection profile. This is neither product
// obligation admission nor a paired performance result.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {workloads} from './fixtures.mjs';
import {registeredLocalEligibility} from './candidate-eligibility.mjs';

const cid = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
const duration = value => Number.isFinite(value) && value >= 0;

// This profile measures Local and fresh DuckDB. Both DuckDB realizations use
// the same registration name, so names alone cannot identify the training
// candidate. Bind the explicit offer policy and the pre-execution choice.
function requireFreshChoices(observation, taskCount) {
  assert.equal(observation.selectionInput?.residentPolicy, false,
    'NativeFreshCalibrationRequiresResidentDisabled');
  const choices = observation.ownerCorrespondence?.observations?.choices;
  assert(Array.isArray(choices), 'MissingNativeCalibrationChoices');
  assert.deepEqual(choices.map(choice => choice.task),
    Array.from({length: taskCount}, (_, index) => index + 1),
    'NativeCalibrationChoiceTasksMismatch');
  for (const [index, choice] of choices.entries()) {
    assert.equal(choice.name, observation.selected[index],
      'NativeCalibrationChoiceMismatch');
    assert.equal(choice.registration, observation.selected[index],
      'NativeCalibrationRegistrationMismatch');
    assert.equal(choice.resident, false,
      'NativeResidentTimingCannotCalibrateFresh');
  }
}

export function admitNativeEstimateProfile({profile, trainingFixture,
  targetFixture, revision, binaryDigest}) {
  assert(profile && trainingFixture && targetFixture,
    'IncompleteNativeEstimateProfile');
  assert.equal(profile.version, 'actql-native-retained-estimate-profile/0.1');
  assert.equal(profile.revision, revision);
  assert.equal(profile.binaryDigest, binaryDigest);
  assert.equal(profile.trainingCaseId, trainingFixture.id);
  assert.equal(profile.targetCaseId, targetFixture.id);
  assert.notEqual(trainingFixture.id, targetFixture.id);
  assert.equal(trainingFixture.workload, targetFixture.workload);
  assert.equal(trainingFixture.layout, targetFixture.layout);
  assert(trainingFixture.rows < targetFixture.rows ||
    targetFixture.rows === 100 && trainingFixture.rows === 1000,
  'InvalidNativeHeldOutTrainingSize');
  assert.equal(profile.trainingSourceDefinitionSha256,
    cid(trainingFixture.createSourceSql));
  assert.equal(profile.targetSourceDefinitionSha256,
    cid(targetFixture.createSourceSql));
  assert.equal(profile.trainingProgramSha256,
    cid(JSON.stringify(trainingFixture.program())));
  assert.equal(profile.targetProgramSha256,
    cid(JSON.stringify(targetFixture.program())));
  const localEligible = registeredLocalEligibility(trainingFixture).eligible;
  assert.equal(registeredLocalEligibility(targetFixture).eligible, localEligible);
  assert.equal(profile.localEligible, localEligible);
  assert.equal(profile.acceptanceEligible, false);
  const taskCount = targetFixture.workload === workloads[1] ? 4 : 3;
  const observations = profile.observations;
  assert(Array.isArray(observations));
  assert.equal(observations.length, localEligible ? 6 : 3);
  const preimage = {revision, trainingCaseId: trainingFixture.id,
    targetCaseId: targetFixture.id, binaryDigest, observations};
  assert.equal(profile.estimateSource, cid(JSON.stringify(preimage)),
    'NativeTrainingIdentityMismatch');
  for (let round = 0; round < 3; round++) {
    const candidates = localEligible
      ? round % 2 ? ['duckdb', 'local'] : ['local', 'duckdb']
      : ['duckdb'];
    for (const [position, candidate] of candidates.entries()) {
      const item = observations[round * candidates.length + position];
      assert.equal(item.round, round);
      assert.equal(item.candidate, candidate);
      assert.equal(item.case, trainingFixture.id);
      assert.equal(item.status, 'verified-diagnostic');
      assert.equal(item.result?.rows_cid, trainingFixture.identity().rowsCid);
      assert.equal(item.result?.task_count, taskCount);
      assert.equal(item.taskIntervals?.length, taskCount);
      assert.deepEqual(item.taskIntervals.map(value => value.task),
        Array.from({length: taskCount}, (_, index) => index + 1));
      assert(item.taskIntervals.every(value =>
        duration(value.elapsedMilliseconds) &&
        Number.isSafeInteger(value.elapsedMicroseconds) &&
        value.elapsedMilliseconds === value.elapsedMicroseconds / 1000));
      assert.deepEqual(item.selected, Array(taskCount).fill(candidate),
        'NativeCandidateTrainingWasNotForced');
      requireFreshChoices(item, taskCount);
      assert(duration(item.cleanupMilliseconds));
      assert.equal(item.selectionInput.localEligible, localEligible);
    }
  }
  const median = values => [...values].sort((a, b) => a - b)[1];
  const rates = candidate => Array.from({length: taskCount}, (_, task) =>
    String(Math.max(1, Math.ceil(median(observations
      .filter(item => item.candidate === candidate)
      .map(item => item.taskIntervals[task].elapsedMilliseconds))))));
  const localRates = localEligible ? rates('local') : null;
  const nativeRates = rates('duckdb');
  assert.deepEqual(profile.localTaskMilliseconds, localRates);
  assert.deepEqual(profile.nativeTaskMilliseconds, nativeRates);
  const ordinary = profile.ordinary;
  assert.equal(ordinary?.case, targetFixture.id);
  assert.equal(ordinary.status, 'verified-diagnostic');
  assert.equal(ordinary.result?.rows_cid, targetFixture.identity().rowsCid);
  assert.equal(ordinary.result?.task_count, taskCount);
  assert.equal(ordinary.selected?.length, taskCount);
  assert(ordinary.selected.every(value => value === 'local' || value === 'duckdb'));
  requireFreshChoices(ordinary, taskCount);
  assert.equal(ordinary.selectionInput.localEligible, localEligible);
  assert.deepEqual(ordinary.selectionInput.localRates,
    localEligible ? localRates : undefined);
  assert.deepEqual(ordinary.selectionInput.nativeRates, nativeRates);
  return Object.freeze({trainingCaseId: trainingFixture.id,
    targetCaseId: targetFixture.id, localEligible,
    localTaskMilliseconds: localRates,
    nativeTaskMilliseconds: nativeRates,
    residentPolicy: false,
    estimateSource: profile.estimateSource,
    scope: 'held-out Native candidate rates; not paired acceptance'});
}
