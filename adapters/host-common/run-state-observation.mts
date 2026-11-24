// Named arguments at the installed Host's Run-state JS bridge. The common MoonBit
// issuer remains the only owner of the state and physical-stop rules.
import {checked} from './runtime-result.mjs';
import type {SynchronousRuntimeData} from './runtime-result.mjs';

// Opaque observations cross the JS target from checked to the same Common
// reader. Public JSON remains DATA until its existing consuming boundary.
type WaitRuntime = {
  clientProgramRunWaitDecision(wire: string, hasSince: boolean, since: bigint): string;
};
type StateObservationRuntime = {
  clientProgramPrepareRunStateObservation(wire: string, runId: string, revision: bigint): SynchronousRuntimeData;
  clientProgramRunStateObservationKey(observation: unknown): string;
  clientProgramRunStateObservationRevision(observation: unknown, hasPrior: boolean,
    prior: string, revision: bigint): SynchronousRuntimeData;
  clientProgramRunStateObservationWire(observation: unknown, revision: bigint): SynchronousRuntimeData;
};
type KeyRuntime = {
  clientProgramRunObservationKey(outcome: string, revision: bigint, hasCleanupPending: boolean,
    cleanupPending: boolean, hasPhysicalStop: boolean, physicalStop: boolean): string | undefined;
};
type UnpublishedStateInput = Readonly<{
  runId: string; observedAt: string; resultNames: readonly string[]; dispatchReserved: boolean;
  preDispatchFailureConfirmed: boolean; cancelledBeforeStart: boolean;
  observedTerminalOutcome: string; executionUnknown: boolean;
}>;
type UnpublishedStateRuntime = {
  clientProgramIssueControlledUnpublishedRunState(runId: string, observedAt: string,
    resultNames: readonly string[], dispatchReserved: boolean, preDispatchFailureConfirmed: boolean,
    cancelledBeforeStart: boolean, observedTerminalOutcome: string, executionUnknown: boolean): SynchronousRuntimeData;
};
type ControlInput = Readonly<{
  revision: number; cancellationRequested: boolean; physicallyUnstarted: boolean;
  preDispatchFailureConfirmed: boolean; physicalCloseConfirmed: boolean;
}>;
type ControlRuntime = {
  clientRunControlObservation(revision: number, cancellationRequested: boolean, physicallyUnstarted: boolean,
    preDispatchFailureConfirmed: boolean, physicalCloseConfirmed: boolean): SynchronousRuntimeData;
};

export function installedRunWaitDecision(moon: WaitRuntime, state: unknown, since: number | null) {
  return moon.clientProgramRunWaitDecision(JSON.stringify(state), since !== null,
    since === null ? 0n : BigInt(since));
}

// The actual request-journal owner supplies the already admitted Run id and
// counter from its original row. No JS canonical identity or state machine.
export function prepareInstalledRunStateObservation(moon: StateObservationRuntime, {
  state, runId, revision, priorKey,
}: Readonly<{state: unknown; runId: string; revision: number; priorKey: string | null}>) {
  const observation = checked(moon.clientProgramPrepareRunStateObservation(
    JSON.stringify(state), runId, BigInt(revision)));
  const key = moon.clientProgramRunStateObservationKey(observation);
  const next = checked(moon.clientProgramRunStateObservationRevision(
    observation, priorKey !== null, priorKey ?? '', BigInt(revision))) as bigint;
  const wire = checked(moon.clientProgramRunStateObservationWire(observation, next)) as string;
  return Object.freeze({key, revision: Number(next), wire});
}

export function issueInstalledRunObservationKey(moon: KeyRuntime, {
  outcome, revision, cleanupPending, physicalCloseConfirmed,
}: Readonly<{outcome: string; revision: number; cleanupPending?: boolean; physicalCloseConfirmed?: boolean}>) {
  // Presence crosses the JS ABI explicitly; MoonBit owns optional values and
  // their projection. Unconfirmed physical cleanup remains an unknown fact.
  const stopped = physicalCloseConfirmed === true;
  return moon.clientProgramRunObservationKey(outcome, BigInt(revision),
    cleanupPending !== undefined, cleanupPending === true, stopped, stopped);
}

export function issueInstalledUnpublishedRunState(moon: UnpublishedStateRuntime, {
  runId, observedAt, resultNames, dispatchReserved,
  preDispatchFailureConfirmed, cancelledBeforeStart,
  observedTerminalOutcome, executionUnknown,
}: UnpublishedStateInput): unknown {
  return JSON.parse(checked(
    moon.clientProgramIssueControlledUnpublishedRunState(
      runId, observedAt, resultNames, dispatchReserved,
      preDispatchFailureConfirmed, cancelledBeforeStart,
      observedTerminalOutcome, executionUnknown)) as string);
}

export function issueInstalledRunControlObservation(moon: ControlRuntime, {
  revision, cancellationRequested, physicallyUnstarted,
  preDispatchFailureConfirmed, physicalCloseConfirmed,
}: ControlInput): unknown {
  try {
    return JSON.parse(checked(moon.clientRunControlObservation(
      revision, cancellationRequested, physicallyUnstarted,
      preDispatchFailureConfirmed, physicalCloseConfirmed)) as string);
  } catch (cause) {
    // Keep the installed Host's existing failure identity while exposing the
    // common issuer's typed reason to internal cleanup and diagnostics.
    const failure = new Error('InvalidRunControl', {cause}) as Error & {
      operation: 'issue_run_control_observation'; primaryFailure: unknown;
    };
    failure.operation = 'issue_run_control_observation';
    failure.primaryFailure = (cause as {cause?: unknown} | undefined)?.cause ?? cause;
    throw failure;
  }
}
