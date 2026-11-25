import assert from 'node:assert/strict';
import test from 'node:test';
import {issueInstalledRunControlObservation, issueInstalledRunObservationKey,
  issueInstalledUnpublishedRunState} from './run-state-observation.mjs';

const state = Object.freeze({runId: 'run-a',
  observedAt: '2026-09-30T00:00:00.000Z', resultNames: ['answer'],
  dispatchReserved: true, preDispatchFailureConfirmed: false,
  cancelledBeforeStart: false, observedTerminalOutcome: 'none',
  executionUnknown: true});
const control = Object.freeze({revision: 3, cancellationRequested: true,
  physicallyUnstarted: false, preDispatchFailureConfirmed: false,
  physicalCloseConfirmed: false});

test('installed Run keys marshal absence separately and retain common refusal', () => {
  const calls: Parameters<Parameters<typeof issueInstalledRunObservationKey>[0]['clientProgramRunObservationKey']>[] = [];
  const moon = {clientProgramRunObservationKey(...args: Parameters<Parameters<
    typeof issueInstalledRunObservationKey>[0]['clientProgramRunObservationKey']>) {
    calls.push(args);
    return undefined;
  }};
  for (const [cleanupPending, physicalCloseConfirmed] of [
    [undefined, undefined], [undefined, false], [false, false],
    [true, true], [false, true],
  ] as const) {
    assert.equal(issueInstalledRunObservationKey(moon, {
      outcome: 'running', revision: 7, cleanupPending, physicalCloseConfirmed,
    }), undefined);
  }
  assert.deepEqual(calls, [
    ['running', 7n, false, false, false, false],
    ['running', 7n, false, false, false, false],
    ['running', 7n, true, false, false, false],
    ['running', 7n, true, true, true, true],
    ['running', 7n, true, false, true, true],
  ]);
});

test('installed Run observations name each physical-control input', () => {
  let stateArgs: Parameters<Parameters<typeof issueInstalledUnpublishedRunState>[0]['clientProgramIssueControlledUnpublishedRunState']> | undefined;
  let controlArgs: Parameters<Parameters<typeof issueInstalledRunControlObservation>[0]['clientRunControlObservation']> | undefined;
  const moon = {
    clientProgramIssueControlledUnpublishedRunState(...args: NonNullable<typeof stateArgs>) {
      stateArgs = args;
      return {$tag: 1, _0: '{"status":"needs_reconciliation"}'};
    },
    clientRunControlObservation(...args: NonNullable<typeof controlArgs>) {
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

type RunControlFailure = {message: string; operation: string; primaryFailure: {code?: string};
  cause: {code?: string; cause?: unknown}};
test('installed Run control retains the common issuer failure', () => {
  const issue = Object.freeze({kind: 'ActionStatusMismatch'});
  const moon = {clientRunControlObservation: () => ({$tag: 0, _0: issue})};
  assert.throws(() => issueInstalledRunControlObservation(moon, control),
    (error: unknown) => {
      assert.equal((error as RunControlFailure).message, 'InvalidRunControl');
      assert.equal((error as RunControlFailure).operation, 'issue_run_control_observation');
      assert.equal((error as RunControlFailure).primaryFailure, issue);
      assert.equal((error as RunControlFailure).cause.code, 'MoonBitHostFailure');
      assert.equal((error as RunControlFailure).cause.cause, issue);
      return true;
    });
});

test('an absent JS bridge result remains a fault, not a missing Run', () => {
  const moon = {clientRunControlObservation: () => undefined};
  assert.throws(() => issueInstalledRunControlObservation(moon, control),
    (error: unknown) => {
      assert.equal((error as RunControlFailure).message, 'InvalidRunControl');
      assert.equal((error as RunControlFailure).primaryFailure.code, 'InvalidHostRuntimeResult');
      return true;
    });
});
