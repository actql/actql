import assert from 'node:assert/strict';
import test from 'node:test';
import {issueInstalledRunControlObservation,
  issueInstalledUnpublishedRunState} from './run-state-observation.mjs';

const state = Object.freeze({runId: 'run-a',
  observedAt: '2026-09-30T00:00:00.000Z', resultNames: ['answer'],
  dispatchReserved: true, preDispatchFailureConfirmed: false,
  cancelledBeforeStart: false, observedTerminalOutcome: 'none',
  executionUnknown: true});
const control = Object.freeze({revision: 3, cancellationRequested: true,
  physicallyUnstarted: false, preDispatchFailureConfirmed: false,
  physicalCloseConfirmed: false});

test('installed Run observations name each physical-control input', () => {
  let stateArgs;
  let controlArgs;
  const moon = {
    clientProgramIssueControlledUnpublishedRunState(...args) {
      stateArgs = args;
      return {$tag: 1, _0: '{"status":"needs_reconciliation"}'};
    },
    clientRunControlObservation(...args) {
      controlArgs = args;
      return {$tag: 1, _0: '{"physical_stop":"unknown"}'};
    },
  };
  assert.deepEqual(issueInstalledUnpublishedRunState(moon, state),
    {status: 'needs_reconciliation'});
  assert.deepEqual(stateArgs, ['run-a', state.observedAt, ['answer'],
    true, false, false, 'none', true]);
  assert.deepEqual(issueInstalledRunControlObservation(moon, control),
    {physical_stop: 'unknown'});
  assert.deepEqual(controlArgs, [3, true, false, false, false]);
});

test('installed Run control retains the common issuer failure', () => {
  const issue = Object.freeze({kind: 'ActionStatusMismatch'});
  const moon = {clientRunControlObservation: () => ({$tag: 0, _0: issue})};
  assert.throws(() => issueInstalledRunControlObservation(moon, control),
    error => {
      assert.equal(error.message, 'InvalidRunControl');
      assert.equal(error.operation, 'issue_run_control_observation');
      assert.equal(error.primaryFailure, issue);
      assert.equal(error.cause.code, 'MoonBitHostFailure');
      assert.equal(error.cause.cause, issue);
      return true;
    });
});

test('an absent JS bridge result remains a fault, not a missing Run', () => {
  const moon = {clientRunControlObservation: () => undefined};
  assert.throws(() => issueInstalledRunControlObservation(moon, control),
    error => {
      assert.equal(error.message, 'InvalidRunControl');
      assert.equal(error.primaryFailure.code, 'InvalidHostRuntimeResult');
      return true;
    });
});
