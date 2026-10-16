// Named arguments at the installed Host's Run-state JS bridge. The common MoonBit
// issuer remains the only owner of the state and physical-stop rules.
import {checked} from './runtime-result.mjs';

// The actual request-journal owner supplies the already admitted Run id and
// counter from its original row. No JS canonical identity or state machine.
export function prepareInstalledRunStateObservation(moon, {
  state, runId, revision, priorKey,
}) {
  const observation = checked(moon.clientProgramPrepareRunStateObservation(
    JSON.stringify(state), runId, BigInt(revision)));
  const key = moon.clientProgramRunStateObservationKey(observation);
  const next = checked(moon.clientProgramRunStateObservationRevision(
    observation, priorKey !== null, priorKey ?? '', BigInt(revision)));
  const wire = checked(moon.clientProgramRunStateObservationWire(observation, next));
  return Object.freeze({key, revision: Number(next), wire});
}

export function issueInstalledRunObservationKey(moon, {
  outcome, revision, cleanupPending, physicalCloseConfirmed,
}) {
  // Presence crosses the JS ABI explicitly; MoonBit owns optional values and
  // their projection. Unconfirmed physical cleanup remains an unknown fact.
  const stopped = physicalCloseConfirmed === true;
  return moon.clientProgramRunObservationKey(outcome, BigInt(revision),
    cleanupPending !== undefined, cleanupPending === true, stopped, stopped);
}

export function issueInstalledUnpublishedRunState(moon, {
  runId, observedAt, resultNames, dispatchReserved,
  preDispatchFailureConfirmed, cancelledBeforeStart,
  observedTerminalOutcome, executionUnknown,
}) {
  return JSON.parse(checked(
    moon.clientProgramIssueControlledUnpublishedRunState(
      runId, observedAt, resultNames, dispatchReserved,
      preDispatchFailureConfirmed, cancelledBeforeStart,
      observedTerminalOutcome, executionUnknown)));
}

export function issueInstalledRunControlObservation(moon, {
  revision, cancellationRequested, physicallyUnstarted,
  preDispatchFailureConfirmed, physicalCloseConfirmed,
}) {
  try {
    return JSON.parse(checked(moon.clientRunControlObservation(
      revision, cancellationRequested, physicallyUnstarted,
      preDispatchFailureConfirmed, physicalCloseConfirmed)));
  } catch (cause) {
    // Keep the installed Host's existing failure identity while exposing the
    // common issuer's typed reason to internal cleanup and diagnostics.
    const failure = new Error('InvalidRunControl', {cause});
    failure.operation = 'issue_run_control_observation';
    failure.primaryFailure = cause?.cause ?? cause;
    throw failure;
  }
}
