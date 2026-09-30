// Named arguments at the installed Host's Run-state JS bridge. The common MoonBit
// issuer remains the only owner of the state and physical-stop rules.
import {checked} from './runtime-result.mjs';

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
