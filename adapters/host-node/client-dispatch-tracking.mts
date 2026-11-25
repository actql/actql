import {runtimeOptionalField, runtimeTag} from '../host-common/compiler-binding.generated.mjs';
import {CapturedRunPublicationError} from './entry.mjs';
import {dispatchFailureSnapshot, dispatchFailureCodeSite} from './client-dispatch-diagnostic.mjs';

type DispatchRef = Readonly<{runDefinitionCid: string}>;
type Outcome = 'failed' | 'cancelled' | null;
type CleanupOwner = Readonly<{
  close(): unknown; cleanup(): unknown; cleanupPending(): unknown;
}>;
type CleanupHandle = Readonly<{
  status(): Readonly<{pending: boolean}> | undefined; retry(): unknown;
}>;
type TrackedEntry<Ref extends DispatchRef> = {
  ref: Ref;
  settled: boolean;
  abort: AbortController;
  observeStopped?: (outcome: Outcome) => unknown;
  physicalStarted?: boolean;
  physicalWorkMayHaveStarted?: boolean;
  stopObserved?: boolean;
  stopObservationPending?: boolean;
  cleanupOwner?: CleanupOwner;
  cleanupHandle?: CleanupHandle;
  unresolvedCleanup?: boolean;
  runInvoked?: boolean;
  promise?: Promise<unknown>;
  terminalOutcome?: Outcome;
  primaryFailure?: unknown;
  closeFailure?: unknown;
  cleanupFailure?: unknown;
  finishFailure?: unknown;
  releaseFailure?: unknown;
  preparationRetirementFailure?: unknown;
};
type FailureData = Readonly<{
  cause?: unknown; code?: unknown; cleanupPending?: unknown; cleanupHandle?: CleanupHandle;
}>;
type SourceInput = Readonly<{
  preparedProgram: unknown; preparedSource: unknown; sourceAccess: unknown;
}>;
type DispatchRun = Readonly<{
  signal: AbortSignal;
  acquireSource(input: SourceInput): unknown;
  beginPhysicalWork(): void;
  observePreEffectFailure(): void;
  retainExecution(execution: CleanupOwner): void;
}>;
type TrackingOptions = Readonly<{
  run(scope: DispatchRun): unknown;
  observeStopped(outcome: Outcome): unknown;
  barrierFailureOutcome?: Outcome;
}>;
type DispatchTracking<Ref extends DispatchRef> = Readonly<{
  entries: Map<string, TrackedEntry<Ref>>;
  keyOf(ref: Ref): string;
  current(ref: Ref): TrackedEntry<Ref> | undefined;
  beforeDispatch?: (ref: Ref) => unknown;
  acquireSource(entry: TrackedEntry<Ref>, preparedProgram: unknown, preparedSource: unknown,
    sourceAccess: unknown, options: {originalEvidence: true}): unknown;
  retainDispatchPrimaryFailure(entry: TrackedEntry<Ref>, result: unknown): void;
  settleCleanup(entry: TrackedEntry<Ref>): unknown;
  settleRetainedEntry(entry: TrackedEntry<Ref>): unknown;
  retire(entry: TrackedEntry<Ref>): void;
  credentialRefusalPending(ref: Ref): boolean;
  diagnostic(name: string, detail: unknown): unknown;
  diagnosticErrorType: ErrorConstructor;
  diagnosticStackFormatter: unknown;
  observation?: Readonly<{retainOperation?(operation: Promise<unknown>): unknown}>;
  beforeDrain?(entry: TrackedEntry<Ref>): void;
}>;

export function createClientDispatchTracking<Ref extends DispatchRef>({entries, keyOf, current,
  beforeDispatch, acquireSource, retainDispatchPrimaryFailure, settleCleanup, settleRetainedEntry,
  retire, credentialRefusalPending, diagnostic, diagnosticErrorType, diagnosticStackFormatter,
  observation, beforeDrain}: DispatchTracking<Ref>) {
  // The installed Effect Run owner supplies the already-admitted operation.
  // This is the same physical supervisor as ordinary dispatch, not another
  // Run-start or Effect retry engine. It never invokes run again during drain.
  // The callback must transfer cleanup custody before any fallible operation
  // that can retain resources. Its common Run observer records the stop
  // independently from waiting, failed, unknown or published outcome.
  const track = (ref: Ref, {run, observeStopped,
    barrierFailureOutcome = null}: TrackingOptions) => {
    if (typeof ref?.runDefinitionCid !== 'string' ||
        typeof run !== 'function' || typeof observeStopped !== 'function') {
      throw new TypeError('InvalidClientOwnedDispatch');
    }
    const existing = current(ref);
    if (existing !== undefined) return existing.promise;
    const entry: TrackedEntry<Ref> = {ref: Object.freeze({...ref}), settled: false,
      abort: new AbortController(), observeStopped,
      // The original Run-start claim does not prove that this continuation
      // began physical work. The installed Site marks that boundary itself.
      physicalStarted: false, physicalWorkMayHaveStarted: false,
      stopObserved: false, stopObservationPending: false,
      cleanupOwner: undefined, cleanupHandle: undefined,
      unresolvedCleanup: false, runInvoked: false};
    entries.set(keyOf(ref), entry);
    entry.promise = Promise.resolve().then(async () => {
      if (beforeDispatch !== undefined) await beforeDispatch(ref);
      entry.abort.signal.throwIfAborted();
      entry.runInvoked = true;
      return run(Object.freeze({
      signal: entry.abort.signal,
      acquireSource({preparedProgram, preparedSource, sourceAccess}: SourceInput) {
        return acquireSource(entry, preparedProgram, preparedSource, sourceAccess, {originalEvidence: true});
      },
      beginPhysicalWork() {
        entry.physicalStarted = true;
        entry.physicalWorkMayHaveStarted = true;
      },
      observePreEffectFailure() {
        // Only the installed opening boundary can assert this: acquisition
        // or Compute failed before the Effect adapter was invoked. This is
        // an outcome observation, not a physical stop or cleanup exemption.
        entry.terminalOutcome = entry.abort.signal.aborted
          ? 'cancelled' : 'failed';
      },
      retainExecution(execution: CleanupOwner) {
        if (entry.cleanupOwner !== undefined &&
            entry.cleanupOwner !== execution) {
          throw new TypeError('ClientDispatchCleanupOwnerAlreadyRetained');
        }
        if (typeof execution?.close !== 'function' ||
            typeof execution?.cleanup !== 'function' ||
            typeof execution?.cleanupPending !== 'function') {
          throw new TypeError('ClientDispatchCleanupOwnerInvalid');
        }
        entry.cleanupOwner = execution;
      },
      }));
    }).then(async result => {
      if ((result as {status?: string} | null | undefined)?.status === 'needs_reconciliation') {
        retainDispatchPrimaryFailure(entry, result);
      }
      // A trusted installed Site may confirm that a pre-Preview refusal
      // performed no external Effect dispatch. Record that observation only
      // after its physical owner has stopped and cleanup has completed.
      if ((result as {status?: string} | null | undefined)?.status === 'failed_without_effect_dispatch' ||
          (result as {status?: string} | null | undefined)?.status === 'failed_effect_set') {
        entry.terminalOutcome = 'failed';
      }
      await settleCleanup(entry);
      return result;
    }).catch(async (cause: FailureData | null | undefined) => {
      if (!Object.hasOwn(entry, 'primaryFailure')) entry.primaryFailure = cause;
      try {
        const original = entry.primaryFailure;
        const primaryFailure = (original instanceof CapturedRunPublicationError
          ? original.primaryFailure : original) as FailureData | null | undefined;
        const issue = primaryFailure?.cause;
        const issueTag = runtimeTag(issue);
        const nestedIssue = runtimeOptionalField(issue, 0);
        const nestedTag = runtimeTag(nestedIssue);
        const leafIssue = runtimeOptionalField(nestedIssue, 0);
        const leafTag = runtimeTag(leafIssue);
        diagnostic('dispatch_failed', {ref: entry.ref,
          code: cause?.code ?? 'ClientDispatchFailed',
          primaryCode: primaryFailure?.code,
          primaryDiagnostic: dispatchFailureSnapshot(primaryFailure)?.primaryDiagnostic ??
            dispatchFailureCodeSite(primaryFailure, diagnosticErrorType, diagnosticStackFormatter),
          issueTag: issueTag === undefined && Number.isSafeInteger(issue) &&
            (issue as number) >= 0 && (issue as number) <= 65535 ? issue : issueTag,
          nestedIssueTag: nestedTag === undefined && Number.isSafeInteger(nestedIssue) &&
            (nestedIssue as number) >= 0 && (nestedIssue as number) <= 65535 ? nestedIssue : nestedTag,
          leafIssueTag: leafTag === undefined && Number.isSafeInteger(leafIssue) &&
            (leafIssue as number) >= 0 && (leafIssue as number) <= 65535 ? leafIssue
            : Number.isSafeInteger(leafTag) && (leafTag as number) >= 0 && (leafTag as number) <= 65535 ? leafTag : undefined});
      } catch { /* Optional diagnostics cannot interrupt original cleanup. */ }
      if (!entry.runInvoked) {
        // A refused execution barrier ran no Site callback. This is a
        // positive no-start observation, not an inferred physical stop.
        entry.terminalOutcome = entry.abort.signal.aborted
          ? 'cancelled' : barrierFailureOutcome;
        entry.stopObservationPending = true;
      }
      if (cause?.cleanupPending === true) {
        if (typeof cause.cleanupHandle?.status === 'function' &&
            typeof cause.cleanupHandle?.retry === 'function') {
          entry.cleanupHandle = cause.cleanupHandle;
        } else if (entry.cleanupOwner === undefined) {
          entry.unresolvedCleanup = true;
        }
      }
      try { await settleCleanup(entry); }
      catch (failure) { entry.cleanupFailure = failure; }
      throw cause;
    }).finally(() => {
      entry.settled = true;
      retire(entry);
    });
    // submit returns its durable RunRef before the owned operation settles.
    // Observation remains available through operation(), without an unhandled
    // rejection when a Client disconnects or never calls wait().
    entry.promise.catch(() => {});
    try {observation?.retainOperation?.(entry.promise);} catch { /* Optional metadata. */ }
    return entry.promise;
  };

  // The accepted initial Run retained a physical preparation, but the nominal
  // credential refusal proves this Model never reached Entry. A wait can help
  // settle that exact stopped owner. It cannot restart dispatch or confirm stop.
  const settleCredentialRefusal = (ref: Ref) => credentialRefusalPending(ref)
    ? settleRetainedEntry(current(ref)!) : undefined;

  const drain = async () => {
    for (;;) {
      const running = [...entries.values()].filter(entry => !entry.settled);
      if (running.length === 0) break;
      if (beforeDrain !== undefined) for (const entry of running) beforeDrain(entry);
      await Promise.allSettled(running.map(entry => entry.promise));
    }
    for (const entry of [...entries.values()]) {
      await settleRetainedEntry(entry);
    }
    if (entries.size > 0) {
      throw Object.assign(new Error('ClientDispatchCleanupPending'), {
        code: 'ClientDispatchCleanupPending',
        pendingRefs: [...entries.values()].map(entry => entry.ref),
        failures: [...entries.values()].map(entry => ({ref: entry.ref,
          primary: dispatchFailureSnapshot(entry.primaryFailure),
          close: dispatchFailureSnapshot(entry.closeFailure),
          cleanup: dispatchFailureSnapshot(entry.cleanupFailure),
          finish: dispatchFailureSnapshot(entry.finishFailure),
          release: dispatchFailureSnapshot(entry.releaseFailure),
          preparation: dispatchFailureSnapshot(entry.preparationRetirementFailure)})),
      });
    }
  };
  return {track, settleCredentialRefusal, drain};
}
