import assert from 'node:assert/strict';
import test from 'node:test';
import {nativeOwnerObservations, admitNativeOwnerObservations} from './native-owner-observations.mjs';

function evidence() {
  const base = {task: 1, planningWork: 0, attempts: 0, holdings: 0, heldBytes: 0,
    reservedExecutionBytes: 0, reservedRetentionBytes: 0, reservedTransferBytes: 0,
    uncertainTransferBytes: 0, environments: 0, imports: 0, borrowedInputs: 0,
    importedRows: 0, unconfirmedEnvironments: 0, importScratchBytes: 0,
    taskDemandBytes: 0, temporaryViews: 0, tables: 0};
  const held = {...base, planningWork: 2, attempts: 3, holdings: 1, heldBytes: 40,
    reservedExecutionBytes: 128, environments: 1, imports: 1, importedRows: 2,
    tables: 2};
  const closed = {...held, heldBytes: 0, reservedExecutionBytes: 0, tables: 0};
  const offer = [1, 'duckdb', '2', 1, '0', '64', '512', '0', [], ['128']];
  return {observations: {
    owners: [{...base, boundary: 'before-task'}, {...held, boundary: 'after-task'},
      {...held, boundary: 'before-close'}, {...closed, boundary: 'after-close'},
      {...closed, boundary: 'duplicate-close'}],
    candidates: [{task: 1, body: ['actql-policy-candidates/0.2', 'program',
      0, 1, true, [[0, '3', '0', '64', '512', [null, offer]]]]}],
    choices: [{task: 1, position: 0, revision: 1, source: 'OfflineLatency',
      registration: 'duckdb', name: 'duckdb', resident: true}],
    explanations: [{task: 1, body: {
      kind: 'host-private-strategy-explanation/0.1', selection_state: 'selected',
      assessment_revision: 1, selection: {dispatch_authorized: true, revision: 1,
        reason: 'estimated_fastest', remaining_at_selection: {position: 0,
          estimated_milliseconds: '3', transfer_bytes: '0', retained_bytes: '64',
          execution_bytes: '512', rejection: null}, tasks: [{task: 1,
          completed: false, capability: 'duckdb', resident_profile: {}}]}}}],
    phases: [{boundary: 'application', elapsedMicroseconds: 4},
      {boundary: 'cleanup-end', elapsedMicroseconds: 20}],
    observerMicroseconds: [1, 1, 1, 1, 1],
    plannerObserverTime: [{task: 1, value: 2}],
    plannerObserverWork: [{task: 1, value: 1}]},
  holdings: [{task: 1, rows: 2, rowsCid: 'oracle', bytes: 12}],
  selected: ['duckdb'], final: {attempts: 3, holdings: 1}};
}
const admit = e => admitNativeOwnerObservations(e.observations, e.holdings,
  e.selected, e.final);

test('resident attempts include environment/import and retention includes metadata', () => {
  const result = admit(evidence());
  assert.deepEqual(result.attempts, [{task: 1, compute: 1, environments: 1,
    imports: 1, canonicalRowsBytes: 12, retainedChargeBytes: 40,
    selectedRetentionBoundBytes: '64', physicalAttempts: 3}]);
  assert.equal(result.observerMicroseconds, 5);
  assert.equal(result.phaseIntervals[1].precedingIntervalMicroseconds, 16);
});
for (const [name, mutate, issue] of [
  ['unattributed attempt', e => { e.observations.owners[1].attempts++; }, /UnattributedNativePhysicalAttempt/],
  ['missing intermediate owner', e => { e.observations.owners.splice(1, 1); }, /MissingNativeOwnerBoundary/],
  ['wrong registration', e => { e.observations.choices[0].registration = 'local'; }, /NativeChoiceRegistrationMismatch/],
  ['explanation for another revision', e => { e.observations.explanations[0].body.selection.revision++; }, /NativeExplanationSelectionMismatch/],
  ['explanation for another assessment', e => { e.observations.explanations[0].body.selection.remaining_at_selection.position++; }, /NativeExplanationAssessmentMismatch/],
  ['post-execution explanation', e => { e.observations.explanations[0].body.selection.tasks[0].completed = true; }, /NativeExplanationTaskMismatch/],
  ['invented selection reason', e => { e.observations.explanations[0].body.selection.reason = 'host_preferred'; }, /NativeExplanationReasonMismatch/],
  ['wrong resident choice', e => { e.observations.choices[0].resident = false; }, /NativeExplanationTaskMismatch/],
  ['early holding release', e => { e.observations.owners[2].heldBytes = 0; }, /NativeHoldingLostBeforeClose/],
  ['early environment release', e => { e.observations.owners[1].reservedExecutionBytes = 0; }, /NativeResidentReservationReleasedEarly/],
  ['duplicate close changes cumulative count', e => { e.observations.owners[4].holdings++; }, /NativeDuplicateCloseChangedOwner/],
  ['excess retention', e => { e.observations.candidates[0].body[5][0][5][1][5] = '30'; }, /NativeHoldingExceedsSelectedBound/],
  ['clock retreat', e => { e.observations.phases[1].elapsedMicroseconds = 1; }, /NativePhaseClockRetreat/],
]) test(`refuse ${name}`, () => {const e = evidence(); mutate(e); assert.throws(() => admit(e), issue);});

test('parse actual owner output and refuse missing observer timings', () => {
  const e = evidence().observations;
  const stdout = e.owners.map(value => 'owner-observation:' + JSON.stringify(value)).join('\n');
  assert.throws(() => nativeOwnerObservations(stdout), /MissingNativeObserverInterval/);
});
