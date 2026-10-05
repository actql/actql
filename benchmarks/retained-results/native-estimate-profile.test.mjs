import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {retainedCase, workloads} from './fixtures.mjs';
import {admitNativeEstimateProfile} from './native-estimate-profile.mjs';

const cid = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
const revision = 'a'.repeat(40);
const binaryDigest = cid('release probe');
const trainingFixture = retainedCase(workloads[0], 'narrow', 1000);
const targetFixture = retainedCase(workloads[0], 'narrow', 100);

function bindTraining(profile) {
  profile.estimateSource = cid(JSON.stringify({revision,
    trainingCaseId: trainingFixture.id, targetCaseId: targetFixture.id,
    binaryDigest, observations: profile.observations}));
}

function example() {
  const observe = (fixture, selected) => ({
    case: fixture.id, status: 'verified-diagnostic',
    result: {rows_cid: fixture.identity().rowsCid, task_count: 3},
    taskIntervals: selected.map((name, index) => ({task: index + 1,
      elapsedMicroseconds: name === 'local' ? 2000 : 5000,
      elapsedMilliseconds: name === 'local' ? 2 : 5})),
    cleanupMilliseconds: 1, selected,
    selectionInput: {localEligible: true, residentPolicy: false},
    ownerCorrespondence: {observations: {choices: selected.map((name, index) =>
      ({task: index + 1, registration: name, name, resident: false}))}},
  });
  const observations = [0, 1, 2].flatMap(round =>
    (round % 2 ? ['duckdb', 'local'] : ['local', 'duckdb']).map(candidate =>
      ({round, candidate, ...observe(trainingFixture, Array(3).fill(candidate))})));
  const ordinary = observe(targetFixture, ['local', 'local', 'local']);
  ordinary.selectionInput.localRates = ['2', '2', '2'];
  ordinary.selectionInput.nativeRates = ['5', '5', '5'];
  const profile = {version: 'actql-native-retained-estimate-profile/0.1',
    revision, binaryDigest, trainingCaseId: trainingFixture.id,
    targetCaseId: targetFixture.id,
    trainingSourceDefinitionSha256: cid(trainingFixture.createSourceSql),
    targetSourceDefinitionSha256: cid(targetFixture.createSourceSql),
    trainingProgramSha256: cid(JSON.stringify(trainingFixture.program())),
    targetProgramSha256: cid(JSON.stringify(targetFixture.program())),
    localEligible: true, acceptanceEligible: false,
    localTaskMilliseconds: ['2', '2', '2'],
    nativeTaskMilliseconds: ['5', '5', '5'], observations, ordinary};
  bindTraining(profile);
  return {profile, trainingFixture, targetFixture, revision, binaryDigest};
}

test('admit explicit fresh training and held-out real choice correspondence', () => {
  const result = admitNativeEstimateProfile(example());
  assert.equal(result.residentPolicy, false);
  assert.deepEqual(result.nativeTaskMilliseconds, ['5', '5', '5']);
});

for (const [name, change, issue] of [
  ['resident DuckDB sharing the fresh registration name', item => {
    item.ownerCorrespondence.observations.choices[0].resident = true;
  }, /NativeResidentTimingCannotCalibrateFresh/],
  ['resident offers enabled despite fresh selection', item => {
    item.selectionInput.residentPolicy = true;
  }, /NativeFreshCalibrationRequiresResidentDisabled/],
  ['missing explicit offer policy', item => {
    delete item.selectionInput.residentPolicy;
  }, /NativeFreshCalibrationRequiresResidentDisabled/],
  ['missing actual choice evidence', item => {
    delete item.ownerCorrespondence;
  }, /MissingNativeCalibrationChoices/],
  ['choice for a different task', item => {
    item.ownerCorrespondence.observations.choices[0].task = 2;
  }, /NativeCalibrationChoiceTasksMismatch/],
  ['name-only substitution', item => {
    item.ownerCorrespondence.observations.choices[0].name = 'local';
  }, /NativeCalibrationChoiceMismatch/],
  ['different actual registration', item => {
    item.ownerCorrespondence.observations.choices[0].registration = 'local';
  }, /NativeCalibrationRegistrationMismatch/],
]) test(`reject training with ${name}, even with a matching training digest`, () => {
  const input = example();
  change(input.profile.observations[1]);
  bindTraining(input.profile);
  assert.throws(() => admitNativeEstimateProfile(input), issue);
});

test('held-out candidate choices obey the same fresh realization boundary', () => {
  const input = example();
  input.profile.ordinary.ownerCorrespondence.observations.choices[0].resident = true;
  assert.throws(() => admitNativeEstimateProfile(input),
    /NativeResidentTimingCannotCalibrateFresh/);
  input.profile.ordinary.ownerCorrespondence.observations.choices[0].resident = false;
  input.profile.ordinary.selectionInput.residentPolicy = true;
  assert.throws(() => admitNativeEstimateProfile(input),
    /NativeFreshCalibrationRequiresResidentDisabled/);
});
