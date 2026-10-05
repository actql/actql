// A measured Native selection input, not an assertion of globally optimal
// planning or performance. Raw Owner/phase observations retain their source
// revision; no profile is retagged for a different candidate checkout.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {retainedCase, workloads} from './fixtures.mjs';
import {nativeCostObservation} from './native-cost-observation.mjs';
import {admitNativeOwnerObservations} from './native-owner-observations.mjs';
import {nativeResidentEstimateArguments} from './native-resident-estimates.mjs';

const digest = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const method = 'three predeclared alternating Native training rounds; median matched task/release cost rounded up to milliseconds';
const kinds = {
  local: ['local', 'local', 'local'], fresh: ['duckdb', 'duckdb', 'duckdb'],
  resident: ['resident', 'resident', 'resident'], mixed: ['local', 'resident', 'resident'],
};

export function nativeResidentCalibrationBasis({trainingFixture, targetFixture, revision, binaryDigest}) {
  assert(/^[0-9a-f]{40}$/.test(revision) && /^sha256:[0-9a-f]{64}$/.test(binaryDigest),
    'InvalidNativeResidentCalibrationIdentity');
  assert.equal(trainingFixture.id, retainedCase(workloads[0], 'narrow', 1000).id,
    'NativeResidentTrainingOutsideSelectedDomain');
  assert.equal(targetFixture.id, retainedCase(workloads[0], 'narrow', 100).id,
    'NativeResidentTargetOutsideSelectedDomain');
  for (const [fixture, rows] of [[trainingFixture, 1000], [targetFixture, 100]]) {
    const registered = retainedCase(workloads[0], 'narrow', rows);
    assert.equal(fixture.createSourceSql, registered.createSourceSql);
    assert.deepEqual(fixture.program(), registered.program());
    assert.deepEqual(fixture.limits, registered.limits);
    assert.deepEqual(fixture.identity(), registered.identity());
  }
  return {version: 'actql-native-resident-estimate-observation/0.1', revision, binaryDigest,
    trainingCaseId: trainingFixture.id, targetCaseId: targetFixture.id,
    trainingSourceDefinitionSha256: digest(trainingFixture.createSourceSql),
    targetSourceDefinitionSha256: digest(targetFixture.createSourceSql),
    trainingProgramSha256: digest(JSON.stringify(trainingFixture.program())),
    targetProgramSha256: digest(JSON.stringify(targetFixture.program())),
    acceptanceEligible: false, method};
}

function checkedObservation(observation, fixture) {
  assert.equal(observation.case, fixture.id, 'NativeResidentObservationCaseMismatch');
  assert.equal(observation.result?.rows_cid, fixture.identity().rowsCid,
    'NativeResidentObservationIdentityMismatch');
  assert.equal(observation.result?.task_count, 3);
  assert.equal(observation.selectionInput?.localEligible, true);
  const correspondence = observation.ownerCorrespondence;
  const choices = correspondence?.observations?.choices;
  assert(Array.isArray(choices), 'MissingNativeResidentCalibrationChoices');
  const owner = admitNativeOwnerObservations(correspondence.observations,
    observation.taskHoldings, choices.map(choice => choice.name), observation.result.usage);
  assert.deepEqual(correspondence, owner, 'NativeResidentOwnerProjectionMismatch');
  const cost = nativeCostObservation(observation);
  return {cost, choices};
}

// Check actual serialized offers, including every represented realization.
// Echoed selectionInput and registration names alone cannot establish this.
export function assertNativeMeasuredOffers(owner, rates, residentEstimates) {
  const offers = owner.observations.candidates[0].body[5]
    .flatMap(candidate => candidate[5].filter(Boolean));
  const represented = new Set();
  for (const offer of offers) {
    const kind = offer[9] !== null ? 'resident' : offer[1] === 'local' ? 'local' : 'fresh';
    assert(['local', 'duckdb'].includes(offer[1]), 'UnexpectedNativeCalibrationRegistration');
    represented.add(`${kind}:${offer[0]}`);
    const expected = kind === 'resident' ? residentEstimates?.taskMilliseconds : rates[kind];
    assert.equal(offer[8][0][1], expected?.[offer[0] - 1], 'MeasuredRateNotInActualOffer');
    if (kind === 'resident') {
      assert.equal(offer[9][1].lines[0].milliseconds, residentEstimates.preparationMilliseconds);
      assert.equal(offer[9][2].lines[0].milliseconds, residentEstimates.cleanupMilliseconds);
      assert.deepEqual(offer[9][3].map(item => item[0].lines[0].milliseconds),
        residentEstimates.importMilliseconds, 'MeasuredImportRatesNotInActualOffer');
    }
  }
  assert.deepEqual([...represented].sort(),
    ['local', 'fresh', ...(residentEstimates ? ['resident'] : [])]
      .flatMap(kind => [1, 2, 3].map(task => `${kind}:${task}`)).sort(),
    'MissingNativeCalibrationRealizationOffers');
}

export function deriveNativeResidentRates(observations, trainingFixture) {
  assert(Array.isArray(observations) && observations.length === 12,
    'IncompleteNativeResidentTraining');
  for (let round = 0; round < 3; round++) {
    const order = round % 2 ? ['mixed', 'resident', 'fresh', 'local'] : ['local', 'fresh', 'resident', 'mixed'];
    for (const [index, leg] of order.entries()) {
      const item = observations[round * 4 + index];
      assert.equal(item.round, round, 'NativeResidentTrainingRoundMismatch');
      assert.equal(item.leg, leg, 'NativeResidentTrainingOrderMismatch');
      const {cost} = checkedObservation(item.observation, trainingFixture);
      assert.deepEqual(item.cost, cost, 'NativeResidentCostProjectionMismatch');
      assert.deepEqual(cost.tasks.map(task => task.realization), kinds[leg],
        'NativeResidentTrainingChoiceMismatch');
      assert.equal(item.observation.selectionInput.residentPolicy,
        leg === 'resident' || leg === 'mixed', 'NativeResidentTrainingPolicyMismatch');
      const selection = item.observation.selectionInput;
      assertNativeMeasuredOffers(item.observation.ownerCorrespondence,
        {local: selection.localRates, fresh: selection.nativeRates}, selection.residentEstimates);
      assert.deepEqual(cost.imports.map(value => value.producer),
        leg === 'resident' ? [0] : leg === 'mixed' ? [0, 1] : [],
        'NativeResidentTrainingImportMismatch');
    }
  }
  const rate = values => {
    assert.equal(values.length, 3, 'IncompleteResidentCalibrationRounds');
    assert(values.every(value => Number.isSafeInteger(value) && value >= 0), 'InvalidCalibrationDuration');
    const value = String(Math.max(1, Math.ceil([...values].sort((a, b) => a - b)[1] / 1000)));
    assert(BigInt(value) <= 2147483647n, 'CalibrationDurationOverflow');
    return value;
  };
  const samples = leg => observations.filter(item => item.leg === leg).map(item => item.cost);
  const tasks = leg => [0, 1, 2].map(index => rate(samples(leg)
    .map(item => item.tasks[index].estimatedMicroseconds)));
  const stages = trainingFixture.program().stages;
  const producers = [...new Set(stages.slice(1).flatMap(stage => Object.values(stage.inputs)
    .map(input => stages.findIndex(candidate => candidate.id === input.result.stage))))].sort();
  assert.deepEqual(producers, [0, 1], 'ResidentCalibrationProducerDomainChanged');
  const residentEstimates = {
    preparationMilliseconds: rate(samples('resident').map(item => item.preparationMicroseconds)),
    cleanupMilliseconds: rate(samples('resident').map(item => item.sharedCleanupMicroseconds)),
    taskMilliseconds: tasks('resident'),
    importMilliseconds: [0, 1, 2, 3].map(producer => producers.includes(producer)
      ? rate(samples(producer === 0 ? 'resident' : 'mixed').map(item => {
        const imports = item.imports.filter(value => value.producer === producer);
        assert.equal(imports.length, 1, 'MissingActualCalibrationImport');
        return imports[0].microseconds;
      })) : null),
  };
  nativeResidentEstimateArguments(residentEstimates, 3);
  return {rates: {local: tasks('local'), fresh: tasks('fresh')}, residentEstimates};
}

export function admitNativeResidentEstimateProfile(input) {
  const {profile, trainingFixture, targetFixture, revision, binaryDigest} = input;
  const basis = nativeResidentCalibrationBasis(input);
  assert.equal(profile?.status, 'completed', 'IncompleteNativeResidentProfile');
  for (const [key, value] of Object.entries(basis)) assert.deepEqual(profile[key], value,
    `NativeResidentProfileMismatch:${key}`);
  assert.equal(profile.estimateSource, digest(JSON.stringify({...basis, observations: profile.observations})),
    'NativeResidentTrainingIdentityMismatch');
  const measured = deriveNativeResidentRates(profile.observations, trainingFixture);
  assert.deepEqual(profile.rates, measured.rates, 'NativeResidentDerivedRatesMismatch');
  assert.deepEqual(profile.residentEstimates, measured.residentEstimates,
    'NativeResidentDerivedSharedRatesMismatch');
  const {cost} = checkedObservation(profile.ordinary.observation, targetFixture);
  assert.equal(profile.ordinary.leg, 'ordinary');
  assert.equal(profile.ordinary.round, 3);
  assert.deepEqual(profile.ordinary.cost, cost, 'NativeResidentHeldOutCostMismatch');
  const selection = profile.ordinary.observation.selectionInput;
  assert.equal(selection.residentPolicy, true);
  assert.deepEqual(selection.localRates, measured.rates.local);
  assert.deepEqual(selection.nativeRates, measured.rates.fresh);
  assert.deepEqual(selection.residentEstimates, measured.residentEstimates);
  assertNativeMeasuredOffers(profile.ordinary.observation.ownerCorrespondence,
    measured.rates, measured.residentEstimates);
  return Object.freeze({admitted: true, revision, binaryDigest,
    estimateSource: profile.estimateSource, trainingCaseId: trainingFixture.id,
    targetCaseId: targetFixture.id, residentPolicy: true, ...measured,
    selected: cost.tasks.map(task => task.realization),
    scope: 'held-out Native realization rates; not paired performance acceptance'});
}
