import {ledgerUsageHasPendingResources} from '../host-common/ledger-usage.mjs';
import {issueInstalledUnpublishedRunState} from '../host-common/run-state-observation.mjs';
import {publicBudgetFailureMessage} from './client-dispatch-diagnostic.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';

type PreparationHostReturn = (holder: unknown) => unknown;
type PreparationHostRuntime = Readonly<{
  clientProgramInstalledManagedPreparationBorrow?: (managedRun: unknown, prepared: unknown, request: unknown) => unknown;
  clientProgramPreparationBorrowRead?: (holder: unknown) => unknown;
  clientProgramPreparationBorrowReturn?: PreparationHostReturn;
}>;
type DispatchPreparationCustody = {
  preparationHostBorrow?: unknown;
  preparationHostReturn?: PreparationHostReturn;
  preparationHostRuntime?: PreparationHostRuntime;
};

type CleanupExecution = Readonly<{
  close: () => unknown;
  cleanup: () => unknown;
  cleanupPending: () => unknown;
}>;
type CleanupHandle = Readonly<{
  status: () => Readonly<{pending: boolean}> | undefined;
  retry: () => unknown;
}>;
type CleanupEntry<Ref> = DispatchPreparationCustody & {
  ref: Ref;
  settled?: boolean;
  cleanupOwner?: CleanupExecution;
  cleanupHandle?: CleanupHandle;
  unresolvedCleanup?: boolean;
  sourceCapture?: Pick<CleanupExecution, 'close'>;
  sourcePreparations?: readonly Readonly<{
    source: unknown;
    prepared: unknown;
    retire: (prepared: unknown) => SynchronousRuntimeData;
  }>[];
  pendingSetup?: unknown;
  stopObservationPending?: boolean;
  failureObservationPending?: boolean;
  finishPending?: boolean;
  releasePending?: boolean;
  physicalStarted?: boolean;
  stopObserved?: boolean;
  physicalWorkMayHaveStarted?: boolean;
  publishingBudgetDiagnostic?: boolean;
  budgetDiagnosticAttempted?: boolean;
  primaryFailure?: unknown;
  retirePreparation?: () => SynchronousRuntimeData;
  preparationRetirementFailure?: unknown;
  acquisitionLedger?: unknown;
  borrowedSources?: boolean;
  closeFailure?: unknown;
  computeStartAttempted?: boolean;
  finished?: () => unknown;
  requestId?: string;
  retainedCleanup?: Promise<void>;
  cleanupFailure?: unknown;
};

type UnpublishedStateInput = Parameters<typeof issueInstalledUnpublishedRunState>[1];
type BudgetFrame = Pick<UnpublishedStateInput, 'dispatchReserved' | 'preDispatchFailureConfirmed'> & Readonly<{
  physicalCloseConfirmed: boolean;
  observedTerminalOutcome: string | null;
  runDefinition: unknown;
  resultNames: UnpublishedStateInput['resultNames'] | undefined;
}>;
type PublishedState = {
  status?: unknown;
  terminal_error?: Readonly<{code?: unknown; message?: unknown}> | null;
};
type BudgetControl = Readonly<{
  runDefinitionRunId: (definition: unknown) => string;
  executionFailureExplanation?: Parameters<typeof publicBudgetFailureMessage>[1];
}>;
type CleanupMoon = Parameters<typeof issueInstalledUnpublishedRunState>[0] & Readonly<{
  strategyHostStop: (setup: unknown) => void;
  strategyHostCloseOutputs: (setup: unknown) => void;
  strategyHostUsage: (setup: unknown) => unknown;
  strategyHostRun: (setup: unknown) => unknown;
  clientProgramPreparationBorrowUsageIsolated?: (holder: unknown, run: unknown) => boolean;
}>;
type CleanupPorts<Ref, Frame extends BudgetFrame> = Readonly<{
  entries: Map<string, CleanupEntry<Ref>>;
  keyOf: (ref: Ref) => string;
  moon: CleanupMoon;
  journal: Readonly<{
    markPreDispatchFailure: (ref: Ref) => void;
    lookupRunDefinition: (ref: Ref, moon: CleanupMoon, control: BudgetControl) => Frame | undefined;
    publishRunState: (frame: Frame, state: PublishedState, moon: CleanupMoon, control: BudgetControl) => void;
  }>;
  control: BudgetControl;
  now: () => string;
  checkpoints?: Readonly<{releaseAcquisition: (requestId: string) => void}>;
  observation?: Readonly<{emit: (phase: 'cleanup', kind: 'cleanup_completed', detail: Readonly<{
    ref: Ref; physicalStop: 'confirmed' | undefined;
  }>) => void}>;
  observeStop: (entry: CleanupEntry<Ref>) => Promise<void>;
  resourceUsage: (ledger: unknown) => unknown;
  diagnostic: (name: 'dispatch_cleanup_completed', detail: Readonly<{ref: Ref; resourceUsage: unknown}>) => void;
}>;

// One original Core holder covers the ordinary configured Host and its
// transitive outputs through confirmed cleanup. This is not a numeric grant.
export function releaseDispatchPreparationHost(entry: DispatchPreparationCustody) {
  const holder = entry.preparationHostBorrow;
  if (holder === undefined) return;
  const release = entry.preparationHostReturn, runtime = entry.preparationHostRuntime;
  entry.preparationHostBorrow = entry.preparationHostReturn = entry.preparationHostRuntime = undefined;
  // A valid Core return consumes its token before any settlement failure;
  // the original retirement receipt retains a failed debit for cleanup retry.
  checked(Reflect.apply(release!, runtime, [holder]));
}
export function retainDispatchPreparationHost(entry: DispatchPreparationCustody,
  moon: PreparationHostRuntime, managedRun: unknown, prepared: unknown, request: unknown,
  hasCustody: boolean) {
  const acquire = moon.clientProgramInstalledManagedPreparationBorrow;
  if (typeof acquire !== 'function') throw new Error('PreparationHostCustodyUnavailable');
  if (entry.preparationHostBorrow !== undefined) throw new Error('DuplicatePreparationHostBorrow');
  const release = moon.clientProgramPreparationBorrowReturn, read = moon.clientProgramPreparationBorrowRead;
  if (typeof release !== 'function' || typeof read !== 'function') throw new Error('PreparationHostCustodyUnavailable');
  const holder = checked(Reflect.apply(acquire, moon, [managedRun, prepared, request]));
  if (holder === undefined) throw new Error('PreparationHostCustodyUnavailable');
  entry.preparationHostBorrow = holder;
  entry.preparationHostReturn = release;
  entry.preparationHostRuntime = moon;
  try {
    if (!hasCustody || Reflect.apply(read, moon, [holder]) !== prepared) {
      throw new Error('ForeignPreparationHostCustody');
    }
  } catch (error) {
    releaseDispatchPreparationHost(entry);
    throw error;
  }
}

// This supervisor settles the resources retained by the original dispatch.
// The supplied stop observer and Journal still own terminal observations.
export function createClientDispatchCleanup<Ref, Frame extends BudgetFrame>({entries, keyOf, moon,
  journal, control, now, checkpoints, observation, observeStop, resourceUsage,
  diagnostic}: CleanupPorts<Ref, Frame>) {
  function retirementReady(entry: CleanupEntry<Ref>) {
    return entry.settled && entry.cleanupOwner === undefined &&
        entry.cleanupHandle === undefined && !entry.unresolvedCleanup &&
        entry.sourceCapture === undefined && entry.sourcePreparations === undefined &&
        entry.pendingSetup === undefined &&
        !entry.stopObservationPending &&
        !entry.failureObservationPending && !entry.finishPending &&
        !entry.releasePending &&
        (!entry.physicalStarted || entry.stopObserved ||
          !entry.physicalWorkMayHaveStarted);
  }

  function retainBudgetFailureObservation(entry: CleanupEntry<Ref>) {
    const message = publicBudgetFailureMessage(entry.primaryFailure,
      control?.executionFailureExplanation);
    if (message === undefined || !entry.stopObserved) return;
    const frame = journal.lookupRunDefinition(entry.ref, moon, control);
    if (frame?.physicalCloseConfirmed !== true || frame.observedTerminalOutcome !== 'failed') return;
    const state = issueInstalledUnpublishedRunState(moon, {
      runId: control.runDefinitionRunId(frame.runDefinition),
      observedAt: now(), resultNames: frame.resultNames!,
      dispatchReserved: frame.dispatchReserved,
      preDispatchFailureConfirmed: frame.preDispatchFailureConfirmed,
      cancelledBeforeStart: false, observedTerminalOutcome: 'failed',
      executionUnknown: false,
    }) as PublishedState;
    if (state.status !== 'failed' || state.terminal_error?.code !== 'ACTQL_E_UNPUBLISHED_RUN') return;
    state.terminal_error = {...state.terminal_error, message};
    // The original journal's exact frame and CAS still own this observation.
    // No successful/pending/Unknown state or cleanup fact is issued here.
    journal.publishRunState(frame, state, moon, control);
  }

  function retire(entry: CleanupEntry<Ref>) {
    if (retirementReady(entry) && !entry.publishingBudgetDiagnostic) {
      if (!entry.budgetDiagnosticAttempted && entry.primaryFailure !== undefined) {
        entry.budgetDiagnosticAttempted = true;
        entry.publishingBudgetDiagnostic = true;
        try { retainBudgetFailureObservation(entry); }
        catch { /* Optional diagnosis cannot mask the primary or block cleanup. */ }
        finally { entry.publishingBudgetDiagnostic = false; }
        if (!retirementReady(entry) || entries.get(keyOf(entry.ref)) !== entry) return;
      }
      try {
        entry.retirePreparation?.();
      } catch (failure) {
        // Keep the original retirement capability and identity for drain.
        // A settled operation alone does not release preparation custody.
        entry.preparationRetirementFailure = failure;
        return;
      }
      entry.retirePreparation = undefined;
      entry.preparationRetirementFailure = undefined;
      const removed = entries.delete(keyOf(entry.ref));
      // This diagnostic describes the complete original owner, not just its
      // physical children. Preparation/finished and acquisition release have
      // now completed under the unchanged retirement predicate above.
      if (removed && entry.acquisitionLedger !== undefined) {
        try {diagnostic('dispatch_cleanup_completed', {ref: entry.ref,
          resourceUsage: resourceUsage(entry.acquisitionLedger)});}
        catch { /* Optional observation cannot restore or prevent retirement. */ }
      }
    }
  }

  async function settleCleanupHandle(entry: CleanupEntry<Ref>) {
    if (entry.cleanupHandle === undefined) return;
    const handle = entry.cleanupHandle;
    if (handle.status()?.pending === true) await handle.retry();
    if (handle.status()?.pending !== false) {
      throw new Error('ClientDispatchCleanupPending');
    }
    entry.cleanupHandle = undefined;
  }

  async function settleCleanup(entry: CleanupEntry<Ref>) {
    const execution = entry.cleanupOwner;
    if (entry.borrowedSources && entry.sourceCapture !== undefined) {
      // Stop Compute before closing any borrowed native input. The same
      // NativePhysical issuer must confirm close before the DAG can release
      // its transferred holding. A failed close retains these exact owners.
      if (execution !== undefined) {
        try { await execution.close(); } catch (failure) { entry.closeFailure ??= failure; }
      }
      if (entry.pendingSetup !== undefined) moon.strategyHostStop(entry.pendingSetup);
      await entry.sourceCapture.close();
      entry.sourceCapture = undefined;
      if (!entry.computeStartAttempted && !entry.unresolvedCleanup) entry.stopObservationPending = true;
    }
    if (entry.pendingSetup !== undefined) {
      moon.strategyHostStop(entry.pendingSetup);
      moon.strategyHostCloseOutputs(entry.pendingSetup);
      if (ledgerUsageHasPendingResources(moon.strategyHostUsage(entry.pendingSetup)) &&
          !(entry.preparationHostBorrow !== undefined &&
            typeof moon.clientProgramPreparationBorrowUsageIsolated === 'function' &&
            moon.clientProgramPreparationBorrowUsageIsolated(entry.preparationHostBorrow, moon.strategyHostRun(entry.pendingSetup)) === true)) {
        throw new Error('ClientDispatchCleanupPending');
      }
      entry.pendingSetup = undefined;
      // This exact setup has stopped and returned its temporary resources.
      // An unentered Compute needs no execution-owner handoff; the existing
      // Run owner still decides the outcome from current durable facts.
      if (entry.physicalStarted && !entry.computeStartAttempted) {
        entry.stopObservationPending = true;
      }
    }
    if (execution !== undefined) {
      if (typeof execution.close !== 'function' ||
          typeof execution.cleanup !== 'function' ||
          typeof execution.cleanupPending !== 'function') {
        throw new Error('ClientDispatchCleanupOwnerInvalid');
      }
      // close may permanently retain its first rejected Promise. Recovery is
      // owned by cleanup, not by invoking close again or repeating Compute.
      try { await execution.close(); }
      catch (failure) { entry.closeFailure ??= failure; }
      // A failed Store consumer can still pin the completed output. Ask the
      // retained Store owner to settle before retrying the execution's
      // reclamation; cancellation alone still grants neither release.
      await settleCleanupHandle(entry);
      const recovered = await execution.cleanup();
      if (recovered === false || execution.cleanupPending() !== false) {
        throw new Error('ClientDispatchCleanupPending');
      }
      entry.cleanupOwner = undefined;
      entry.stopObservationPending = true;
    }
    if (entry.sourceCapture !== undefined) {
      await entry.sourceCapture.close();
      entry.sourceCapture = undefined;
      // Acquisition returned successfully, but evidence/plan preparation can
      // fail before Compute has an owner. Closing that exact capture confirms
      // this physical end; it does not confirm an unowned Compute attempt.
      if (!entry.computeStartAttempted) entry.stopObservationPending = true;
    }
    await settleCleanupHandle(entry);
    if (entry.unresolvedCleanup) {
      throw new Error('ClientDispatchCleanupOwnerMissing');
    }
    if (entry.sourcePreparations !== undefined) {
      for (const {source, prepared, retire} of entry.sourcePreparations) {
        Reflect.apply(retire, source, [prepared]);
      }
      entry.sourcePreparations = undefined;
    }
    if (entry.stopObservationPending) await observeStop(entry);
    if (entry.failureObservationPending) {
      journal.markPreDispatchFailure(entry.ref);
      entry.failureObservationPending = false;
    }
    if (entry.physicalStarted && !entry.stopObserved &&
        entry.physicalWorkMayHaveStarted) {
      throw new Error('ClientDispatchStopUnknown');
    }
    observation?.emit('cleanup', 'cleanup_completed', {ref: entry.ref,
      physicalStop: entry.stopObserved ? 'confirmed' : undefined});
  }

  async function finishRun(entry: CleanupEntry<Ref>) {
    if (!entry.finishPending) return;
    await entry.finished?.();
    entry.finishPending = false;
  }

  function releaseAcquisition(entry: CleanupEntry<Ref>) {
    if (!entry.releasePending) return;
    checkpoints!.releaseAcquisition(entry.requestId!);
    entry.releasePending = false;
  }

  function settleRetainedEntry(entry: CleanupEntry<Ref>) {
    if (entry.retainedCleanup !== undefined) return entry.retainedCleanup;
    entry.retainedCleanup = Promise.resolve().then(async () => {
      try {
        await settleCleanup(entry);
        await finishRun(entry);
        releaseAcquisition(entry);
      } catch (failure) { entry.cleanupFailure = failure; }
      retire(entry);
    }).finally(() => {entry.retainedCleanup = undefined;});
    return entry.retainedCleanup;
  }
  return {retire, settleCleanup, finishRun, releaseAcquisition, settleRetainedEntry};
}
