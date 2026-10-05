// Synthetic admission fixtures, not Native execution or timing evidence.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {retainedCase, workloads} from './fixtures.mjs';
import {admitNativeOwnerObservations} from './native-owner-observations.mjs';
import {admitNativePhysicalPhases} from './native-physical-phases.mjs';
import {nativeCostObservation} from './native-cost-observation.mjs';
import {nativeResidentCalibrationBasis, deriveNativeResidentRates,
  admitNativeResidentEstimateProfile} from './native-resident-estimate-profile.mjs';

const trainingFixture = retainedCase(workloads[0], 'narrow', 1000);
const targetFixture = retainedCase(workloads[0], 'narrow', 100);
const revision = 'a'.repeat(40), binaryDigest = 'sha256:' + 'b'.repeat(64);
const input = {trainingFixture, targetFixture, revision, binaryDigest};
const digest = bytes => 'sha256:' + createHash('sha256').update(bytes).digest('hex');
const resident = {preparationMilliseconds: '1', cleanupMilliseconds: '1',
  taskMilliseconds: ['1', '1', '1'], importMilliseconds: ['1', '1', null, null]};

function observation(fixture, leg, rates, residentEstimates) {
  const selected = leg === 'resident' ? ['resident', 'resident', 'resident'] :
    leg === 'mixed' ? ['local', 'resident', 'resident'] :
      Array(3).fill(leg === 'fresh' ? 'duckdb' : 'local');
  const kinds = ['local', 'fresh', ...(residentEstimates ? ['resident'] : [])];
  const offer = (kind, task) => [task, kind === 'local' ? 'local' : 'duckdb', '2', 1,
    '0', '100', '256', '0', [[[], (kind === 'resident'
      ? residentEstimates.taskMilliseconds : rates[kind])[task - 1]]],
    kind === 'resident' ? ['128', {lines: [{milliseconds: residentEstimates.preparationMilliseconds}]},
      {lines: [{milliseconds: residentEstimates.cleanupMilliseconds}]},
      residentEstimates.importMilliseconds.map(milliseconds => [{lines: [{milliseconds}]}])] : null];
  const assignments = kinds.map((kind, position) => [position, '10', '0', '100', '256',
    [null, ...[1, 2, 3].map(task => offer(kind, task))]]);
  const zero = {task: 1, planningWork: 0, attempts: 0, holdings: 0, heldBytes: 0,
    reservedExecutionBytes: 0, reservedRetentionBytes: 0, reservedTransferBytes: 0,
    uncertainTransferBytes: 0, environments: 0, imports: 0, borrowedInputs: 0,
    importedRows: 0, unconfirmedEnvironments: 0, importScratchBytes: 0,
    taskDemandBytes: 0, temporaryViews: 0, tables: 0};
  const owners = [], choices = [], candidates = [], explanations = [], events = [], intervals = [];
  let current = zero, clock = 0, environment = false;
  const event = (phase, task, producer, boundary) => events.push({phase, task, producer,
    boundary, success: boundary === 'begin' ? null : true,
    elapsedMicroseconds: clock, observerMicroseconds: 0});
  const span = (phase, task, producer, duration) => {
    event(phase, task, producer, 'begin'); clock += duration;
    event(phase, task, producer, 'end');
  };
  for (const [offset, name] of selected.entries()) {
    const task = offset + 1, isResident = name === 'resident';
    const position = kinds.indexOf(isResident ? 'resident' : name === 'local' ? 'local' : 'fresh');
    choices.push({task, position, revision: 1, source: 'OfflineLatency',
      registration: isResident ? 'duckdb' : name, name: isResident ? 'duckdb' : name, resident: isResident});
    candidates.push({task, body: ['actql-policy-candidates/0.1', 'program', 0, 1, true, assignments]});
    explanations.push({task, body: {kind: 'host-private-strategy-explanation/0.1',
      selection_state: 'selected', assessment_revision: 1, selection: {
        dispatch_authorized: true, revision: 1, reason: 'estimated_fastest',
        remaining_at_selection: {position, estimated_milliseconds: '10', transfer_bytes: '0',
          retained_bytes: '100', execution_bytes: '256', rejection: null},
        tasks: [{task, completed: false, capability: isResident ? 'duckdb' : name,
          resident_profile: isResident ? {} : null}]}}});
    owners.push({...current, task, boundary: 'before-task'});
    const start = clock;
    event('task', task, null, 'begin');
    const environments = isResident && !environment ? 1 : 0;
    const imports = isResident && (!environment || leg === 'mixed' && task === 3) ? 1 : 0;
    if (environments) span('environment', task, null, 1000);
    if (imports) span('import', task, leg === 'mixed' && task === 3 ? 1 : 0, 500);
    if (isResident) span('compute', task, null, 3000);
    else clock += name === 'local' ? 2000 : 5000;
    event('task', task, null, 'end');
    intervals.push({task, elapsedMicroseconds: clock - start, elapsedMilliseconds: (clock - start) / 1000});
    clock++;
    environment ||= isResident;
    current = {...current, task, planningWork: current.planningWork + 1,
      attempts: current.attempts + 1 + environments + imports, holdings: current.holdings + 1,
      heldBytes: current.heldBytes + 48, environments: current.environments + environments,
      imports: current.imports + imports, reservedExecutionBytes: environment ? 128 : 0};
    owners.push({...current, boundary: 'after-task'});
  }
  owners.push({...current, boundary: 'before-close'});
  const closed = {...current, heldBytes: 0, reservedExecutionBytes: 0};
  owners.push({...closed, boundary: 'after-close'}, {...closed, boundary: 'duplicate-close'});
  const cleanupStart = clock;
  if (environment) span('environment-close', 0, 0, 100);
  for (const task of [3, 2, 1]) span('task-release', task, null, 500);
  if (environment) span('environment-release', 0, 0, 150);
  const result = {task_count: 3, rows_cid: fixture.identity().rowsCid,
    cleanup_us: clock - cleanupStart + 5, usage: {attempts: current.attempts, holdings: 3}};
  const holdings = [1, 2, 3].map(task => ({task, bytes: 24, rows: 2, rowsCid: fixture.identity().rowsCid}));
  const raw = {owners, choices, candidates, explanations,
    phases: [{boundary: 'application', elapsedMicroseconds: 0}, {boundary: 'cleanup-end', elapsedMicroseconds: clock}],
    observerMicroseconds: owners.map(() => 0),
    plannerObserverTime: [1, 2, 3].map(task => ({task, value: 0})),
    plannerObserverWork: [1, 2, 3].map(task => ({task, value: 1}))};
  const ownerCorrespondence = admitNativeOwnerObservations(raw, holdings,
    choices.map(choice => choice.name), result.usage);
  return {host: 'native', status: 'verified-diagnostic', case: fixture.id,
    result, taskHoldings: holdings, taskIntervals: intervals, ownerCorrespondence,
    selectionInput: {phaseObserver: true, localEligible: true, residentPolicy: Boolean(residentEstimates),
      localRates: rates.local, nativeRates: rates.fresh, residentEstimates},
    physicalPhaseEvents: events, physicalPhases: admitNativePhysicalPhases({events,
      ownerCorrespondence, taskIntervals: intervals, cleanupMicroseconds: result.cleanup_us})};
}

function bind(profile) {
  profile.estimateSource = digest(JSON.stringify({...nativeResidentCalibrationBasis(input), observations: profile.observations}));
}
function example() {
  const observations = [0, 1, 2].flatMap(round => (round % 2
    ? ['mixed', 'resident', 'fresh', 'local'] : ['local', 'fresh', 'resident', 'mixed']).map(leg => {
    const rates = {local: Array(3).fill(leg === 'local' ? '1' : '1000000'),
      fresh: Array(3).fill(leg === 'fresh' ? '1' : '1000000')};
    if (leg === 'mixed') rates.local[0] = '1';
    const profile = leg === 'resident' ? resident : leg === 'mixed'
      ? {...resident, taskMilliseconds: ['1000000', '1', '1']} : undefined;
    const value = observation(trainingFixture, leg, rates, profile);
    return {round, leg, observation: value, cost: nativeCostObservation(value)};
  }));
  const measured = deriveNativeResidentRates(observations, trainingFixture);
  const value = observation(targetFixture, 'local', measured.rates, measured.residentEstimates);
  const profile = {...nativeResidentCalibrationBasis(input), status: 'completed', observations,
    ...measured, ordinary: {round: 3, leg: 'ordinary', observation: value, cost: nativeCostObservation(value)}};
  bind(profile);
  return {...input, profile};
}
test('admit complete realization-bound training and independently fixed duration expectations', () => {
  const result = admitNativeResidentEstimateProfile(example());
  assert.deepEqual(result.rates, {local: ['3', '3', '3'], fresh: ['6', '6', '6']});
  assert.deepEqual(result.residentEstimates, {preparationMilliseconds: '1', cleanupMilliseconds: '1',
    taskMilliseconds: ['4', '4', '4'], importMilliseconds: ['1', '1', null, null]});
  assert.deepEqual(result.selected, ['local', 'local', 'local']);
});
for (const [name, mutate, issue] of [
  ['another revision', value => {value.profile.revision = 'c'.repeat(40);}, /NativeResidentProfileMismatch:revision/],
  ['another binary', value => {value.profile.binaryDigest = 'sha256:' + 'c'.repeat(64);}, /NativeResidentProfileMismatch:binaryDigest/],
  ['partial training', value => {value.profile.observations.pop(); bind(value.profile);}, /IncompleteNativeResidentTraining/],
  ['reordered rounds', value => {value.profile.observations.reverse(); bind(value.profile);}, /NativeResidentTrainingRoundMismatch/],
  ['rate changed without observations', value => {value.profile.rates.local[0] = '1';}, /NativeResidentDerivedRatesMismatch/],
  ['invented import for unused producer', value => {value.profile.residentEstimates.importMilliseconds[2] = '1';}, /NativeResidentDerivedSharedRatesMismatch/],
  ['name-only resident/fresh swap', value => {
    value.profile.observations[2].observation.ownerCorrespondence.observations.choices[0].resident = false; bind(value.profile);
  }, /NativeExplanationTaskMismatch/],
  ['early holding release', value => {
    value.profile.observations[0].observation.ownerCorrespondence.observations.owners.at(-3).heldBytes = 0; bind(value.profile);
  }, /NativeHoldingLostBeforeClose/],
  ['altered phase projection', value => {
    value.profile.observations[0].cost.tasks[0].estimatedMicroseconds++; bind(value.profile);
  }, /NativeResidentCostProjectionMismatch/],
  ['missing underlying events', value => {
    delete value.profile.observations[0].observation.physicalPhaseEvents; bind(value.profile);
  }, /MissingNativePhysicalPhaseEvents/],
  ['target changed with training unchanged', value => {value.profile.ordinary.observation.case = trainingFixture.id;}, /NativeResidentObservationCaseMismatch/],
  ['held-out input rates changed', value => {value.profile.ordinary.observation.selectionInput.localRates = ['1', '1', '1'];}, /Expected values to be strictly deep-equal/],
  ['actual offer changed while input remains', value => {
    value.profile.ordinary.observation.ownerCorrespondence.observations.candidates[0].body[5][0][5][1][8][0][1] = '1';
  }, /MeasuredRateNotInActualOffer/],
]) test(`reject ${name}`, () => {
  const value = example(); mutate(value);
  assert.throws(() => admitNativeResidentEstimateProfile(value), issue);
});
