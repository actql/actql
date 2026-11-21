// Invocation-local evidence for the existing physical Request Journal.
import {validSubmissionRef} from '../../packages/client-wire/index.mjs';
import type {WireCancellationRef, WireSubmissionRef} from '../../packages/client-wire/index.js';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import type {createSqliteTransaction} from '../host-common/sqlite-transaction.mjs';
import {cid, text} from './client-request-journal-records.mjs';
import {fail} from './client-request-journal-sql.mjs';

type RejectionKind = 'conflict' | 'refused';
type SubmissionReason = 'intent' | 'restart_decision' | 'admission_capacity' | 'epoch_expired' | 'epoch_not_yet_valid';
type CancellationReason = 'intent' | 'control_revision' | 'admission_capacity';
type Rejection<Reason> = Readonly<{kind: RejectionKind; reason: Reason; ticket: object | undefined}>;
type ObservedFailure = Readonly<{code?: string; cause?: unknown; outcome?: unknown;
  rollbackCause?: unknown; stateCause?: unknown}>;
type AttemptCandidate = Readonly<{attemptId?: unknown; operation?: unknown}>;
type AttemptOptions = Readonly<{attemptRef?: AttemptCandidate | null; currentAuthorization?: unknown}>;
type SubmissionAttemptResult = Readonly<{requestId?: unknown; observation?: unknown; then?: never}>;
type CancellationCandidate = Readonly<Partial<Record<keyof WireCancellationRef, unknown>>>;
type CancellationTarget = Pick<CancellationCandidate, 'namespaceId' | 'authorityScopeCid' | 'runDefinitionCid'>;
type CancellationOptions = Readonly<{cancelId?: unknown; expectedRevision?: unknown; currentAuthorization?: unknown}>;
type RecordedCancellation = Readonly<{cancellation: Readonly<{kind: string}>; recorded: boolean; then?: never}>;

export const validCancellationRef = (ref: CancellationCandidate | null | undefined): ref is WireCancellationRef =>
  text(ref?.namespaceId) && cid(ref?.authorityScopeCid) && cid(ref?.runDefinitionCid) &&
  text(ref?.cancelId) && Number.isInteger(ref?.expectedRevision) &&
  (ref.expectedRevision as number) >= 0 && (ref.expectedRevision as number) <= 2147483647;
export const ownedCancellationRef = (ref: CancellationCandidate) => Object.freeze({namespaceId: ref.namespaceId,
  authorityScopeCid: ref.authorityScopeCid, runDefinitionCid: ref.runDefinitionCid,
  cancelId: ref.cancelId, expectedRevision: ref.expectedRevision});

export function createJournalAttempts(transaction: ReturnType<typeof createSqliteTransaction>, ensureOpen: () => void) {
  // Only an explicit semantic rejection from this Owner, followed by a
  // confirmed rollback of initial admission, can certify this invocation.
  // An error code copied from another operation carries no such custody.
  const cancellationRejectionCandidates = new WeakMap<Error, Rejection<CancellationReason>>();
  const cancellationRejections = new WeakMap<Error, Rejection<CancellationReason>>();
  const submissionRejectionCandidates = new WeakMap<Error, Rejection<SubmissionReason>>();
  const submissionRejections = new WeakMap<Error, Rejection<SubmissionReason>>();
  let activeSubmissionAttempt: object | undefined;
  const rejectSubmission = (code: string, kind: RejectionKind, reason: SubmissionReason): never => {
    const error = Object.assign(new Error(code), {code});
    submissionRejectionCandidates.set(error, Object.freeze({kind, reason,
      ticket: activeSubmissionAttempt}));
    throw error;
  };
  const submissionTransaction = <Result extends SynchronousRuntimeData>(action: () => Result): Result => {
    try {return transaction.run(action);}
    catch (error) {
      const rejection = submissionRejectionCandidates.get(error as Error);
      if (rejection !== undefined && rejection.ticket === activeSubmissionAttempt &&
          (error as ObservedFailure).outcome !== 'unknown' && transaction.connectionUsable) {
        // transaction.run returns the original semantic error only after a
        // successful rollback. Commit and rollback failures wrap that error.
        submissionRejections.set(error as Error, rejection);
      }
      throw error;
    }
  };
  const submissionAttempt = <Intent, Control, Result extends SubmissionAttemptResult>(
    submissionRef: unknown, intent: Intent, options: AttemptOptions, control: Control, action: () => Result,
    kind: 'checked' | 'recorded',
    originalIntent: (intent: Intent, control: Control, epoch: WireSubmissionRef['epoch']) => Readonly<{identity: string}>) => {
    ensureOpen();
    const attemptRef = options.attemptRef;
    if (!validSubmissionRef(submissionRef) || attemptRef === null ||
        typeof attemptRef !== 'object' ||
        Object.keys(attemptRef).sort().join(',') !== 'attemptId,operation' ||
        attemptRef.operation !== 'submit' || !text(attemptRef.attemptId) ||
        !attemptRef.attemptId.isWellFormed() || typeof options.currentAuthorization !== 'boolean') {
      fail('InvalidClientSubmissionAttempt');
    }
    const ownedAttempt = Object.freeze({operation: 'submit' as const, attemptId: attemptRef.attemptId});
    if (!options.currentAuthorization) return Object.freeze({kind: 'refused' as const,
      attemptRef: ownedAttempt, guarantee: 'attempt_uncommitted_unconsumed' as const, reason: 'authorization' as const});
    const original = originalIntent(intent, control, submissionRef.epoch);
    const ownedRef = Object.freeze({...submissionRef, epoch: Object.freeze({...submissionRef.epoch})});
    const ticket = {}, previous = activeSubmissionAttempt;
    activeSubmissionAttempt = ticket;
    try {
      const result = action();
      return Object.freeze({kind, attemptRef: ownedAttempt,
        ...(kind === 'checked' ? {requestId: result.requestId} : {submission: result,
          attemptKind: result.observation})});
    } catch (error) {
      const rejection = submissionRejections.get(error as Error);
      if (rejection === undefined || rejection.ticket !== ticket) throw error;
      return Object.freeze({kind: rejection.kind, reason: rejection.reason, attemptRef: ownedAttempt,
        submissionRef: ownedRef, intentCid: original.identity,
        ...(rejection.kind === 'refused' ? {guarantee: 'attempt_uncommitted_unconsumed' as const} : {})});
    } finally {activeSubmissionAttempt = previous;}
  };
  const rejectSubmissionEpoch = (validity: 'expired' | 'not_yet_valid'): never => {
    const reason = validity === 'expired' ? 'epoch_expired' : 'epoch_not_yet_valid';
    const code = validity === 'expired' ? 'ClientSubmissionEpochExpired' : 'ClientSubmissionEpochNotYetValid';
    const error = Object.assign(new Error(code), {code});
    // This decision follows a successful transaction which confirmed that
    // this fresh identity has no retained receipt. The clock observation is
    // durable, but no intent custody was consumed by this invocation.
    submissionRejections.set(error, Object.freeze({kind: 'refused', reason,
      ticket: activeSubmissionAttempt}));
    throw error;
  };
  let activeCancellationAttempt: object | undefined;
  const rejectCancellation = (code: string, kind: RejectionKind, reason: CancellationReason): never => {
    const error = Object.assign(new Error(code), {code});
    cancellationRejectionCandidates.set(error, Object.freeze({kind, reason,
      ticket: activeCancellationAttempt}));
    throw error;
  };
  const transact = <Result extends SynchronousRuntimeData>(operation: string, unknownCode: string,
    known: (error: unknown) => boolean, action: () => Result): Result => {
    try { return transaction.run(action); }
    catch (error) {
      const transactionFailure = ([
        'ClientRequestJournalCommitOutcomeUnknown',
        'ClientRequestJournalRollbackFailed',
        'ClientRequestJournalConnectionUnusable',
      ] as readonly (string | undefined)[]).includes((error as ObservedFailure)?.code);
      if (!transactionFailure && known(error) &&
          (error as ObservedFailure).outcome !== 'unknown' &&
          transaction.connectionUsable) {
        const rejection = cancellationRejectionCandidates.get(error as Error);
        if (operation === 'cancel_admission' && rejection !== undefined &&
            rejection.ticket === activeCancellationAttempt) {
          cancellationRejections.set(error as Error, rejection);
        }
        throw error;
      }
      throw Object.assign(new Error(unknownCode, {
        cause: (error as ObservedFailure).cause ?? error,
      }), {
        code: unknownCode, operation,
        outcome: (error as ObservedFailure).outcome ?? 'failed',
        rollbackCause: (error as ObservedFailure).rollbackCause,
        stateCause: (error as ObservedFailure).stateCause,
        connectionUsable: transaction.connectionUsable,
      });
    }
  };

  const cancellationAttempt = <RequestControl, PublicationControl, Result extends RecordedCancellation>(
    journal: {recordCancellationOperation(ref: CancellationTarget, options: CancellationOptions,
      requestControl: RequestControl, publicationControl: PublicationControl): Result},
    ref: CancellationTarget, attemptRef: AttemptCandidate | null | undefined, options: CancellationOptions,
    requestControl: RequestControl, publicationControl: PublicationControl) => {
    ensureOpen();
    if (attemptRef === null || typeof attemptRef !== 'object' ||
        Object.keys(attemptRef).sort().join(',') !== 'attemptId,operation' ||
        attemptRef.operation !== 'cancel' || !text(attemptRef.attemptId) ||
        !attemptRef.attemptId.isWellFormed() ||
        !validCancellationRef({...ref, cancelId: options.cancelId,
          expectedRevision: options.expectedRevision}) ||
        typeof options.currentAuthorization !== 'boolean') {
      fail('InvalidClientCancellationAttempt');
    }
    const ownedAttempt = Object.freeze({operation: 'cancel' as const, attemptId: attemptRef.attemptId});
    if (!options.currentAuthorization) return Object.freeze({
      kind: 'refused' as const, attemptRef: ownedAttempt,
      guarantee: 'attempt_uncommitted_unconsumed' as const, reason: 'authorization' as const,
    });
    const ticket = {};
    const previousAttempt = activeCancellationAttempt;
    activeCancellationAttempt = ticket;
    try {
      const result = journal.recordCancellationOperation(ref, options, requestControl, publicationControl);
      return Object.freeze({kind: result.cancellation.kind === 'accepted'
        ? 'accepted' as const : 'already_satisfied' as const, attemptRef: ownedAttempt,
        cancellation: result.cancellation, recorded: result.recorded});
    } catch (error) {
      const rejection = cancellationRejections.get(error as Error);
      if (rejection === undefined || rejection.ticket !== ticket) throw error;
      return Object.freeze({kind: rejection.kind, reason: rejection.reason, attemptRef: ownedAttempt,
        ...(rejection.kind === 'refused' ? {guarantee: 'attempt_uncommitted_unconsumed' as const} : {}),
        cancelRef: ownedCancellationRef({...ref, cancelId: options.cancelId,
          expectedRevision: options.expectedRevision})});
    } finally { activeCancellationAttempt = previousAttempt; }
  };
  return {rejectSubmission, submissionTransaction, submissionAttempt, rejectSubmissionEpoch,
    rejectCancellation, transact, cancellationAttempt};
}
