// Invocation-local evidence for the existing physical Request Journal.
import {createHash} from 'node:crypto';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {validSubmissionRef} from '../../packages/client-wire/index.mjs';
import type {WireCancellation, WireCancellationRef, WireRunRef, WireSubmissionRef} from '../../packages/client-wire/index.js';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import type {createSqliteTransaction} from '../host-common/sqlite-transaction.mjs';
import {assertJournalCancellationCustody, assertJournalSubmissionCustody,
  type snapshotJournalConfiguration} from './client-request-journal-format.mjs';
import {admission, cid, retainedIdentity, retainedRunFacts, text} from './client-request-journal-records.mjs';
import {fail, type JournalSqlConnection} from './client-request-journal-sql.mjs';

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
type RecordedCancellation = Readonly<{cancellation: WireCancellation; recorded: boolean; then?: never}>;

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

type RunFacts = ReturnType<typeof retainedRunFacts>;
type CancellationIdentity = Exclude<SynchronousRuntimeData, void>;
type CancellationRequestControl = Parameters<typeof retainedIdentity>[1] & Readonly<{
  clientCancellationAdmitRecord(namespace: string, authority: string, cancelId: string,
    definition: RunFacts['runDefinition'], expectedRevision: number): SynchronousRuntimeData;
  clientCancellationIntentCid(identity: CancellationIdentity): string;
  clientCancellationOperationAction(requested: CancellationIdentity, retained: CancellationIdentity,
    exists: boolean, definition: RunFacts['runDefinition'], revision: number,
    authorized: boolean, completed: boolean, cancelled: boolean): number;
  clientRunCancellationAction(definition: RunFacts['runDefinition'], definitionCid: string,
    authorized: boolean, completed: boolean, cancelled: boolean): number;
}>;
type CancellationPublicationControl = Parameters<typeof retainedRunFacts>[1] &
  Readonly<{runDefinitionRunId(definition: RunFacts['runDefinition']): string}>;
type JournalStatement = ReturnType<JournalSqlConnection['prepare']>;
type JournalRow = NonNullable<ReturnType<JournalStatement['get']>>;
// The selected statement supplies raw SQLite data. The existing retained
// identity and Run guards below still establish the original admission.
type StoredRunRow = Parameters<typeof retainedIdentity>[0] & Parameters<typeof retainedRunFacts>[0] &
  Parameters<typeof admission>[0] & Readonly<{revision: number}>;
type CancellationAuthorization = Readonly<{currentAuthorization: unknown; publicationCommitted: unknown}>;
type CancellationRecordOptions = CancellationAuthorization & Readonly<{
  cancelId: unknown; expectedRevision: unknown;
  modelCancellationOwner?: Readonly<{
    fenceRunCancellation(request: Readonly<{originalRunWire: string}>): SynchronousRuntimeData;
    modelCancellationFenced(runId: string, runDefinitionCid: string): unknown;
  }>;
}>;
type CancellationStatements = Readonly<{
  selectRef: Pick<JournalStatement, 'get'>; requestUsage: JournalStatement; submissionIssued: JournalStatement;
  cancellationUsage: JournalStatement; cancellationIssued: JournalStatement;
  cancellationSelect: JournalStatement; cancellationInsert: JournalStatement;
}>;
type CancellationAttempts = Pick<ReturnType<typeof createJournalAttempts>, 'transact' | 'rejectCancellation'>;
type CancellationConfiguration = Pick<ReturnType<typeof snapshotJournalConfiguration>, 'maxRecords' | 'maxRunDefinitionWireBytes'> &
  Readonly<{updateOriginalControl?: Parameters<typeof retainedRunFacts>[3]}>;

export function createJournalCancellation(database: JournalSqlConnection,
  {selectRef, requestUsage, submissionIssued, cancellationUsage, cancellationIssued,
    cancellationSelect, cancellationInsert}: CancellationStatements,
  ensureOpen: () => void, {transact, rejectCancellation}: CancellationAttempts,
  {maxRecords, maxRunDefinitionWireBytes, updateOriginalControl}: CancellationConfiguration) {
  const cancellationKnownFailure = (error: unknown) => ([
    'ClientCancellationDenied', 'ClientCancellationIntentConflict',
    'ClientCancellationRevisionConflict', 'ClientRequestJournalCapacity',
  ] as readonly (string | undefined)[]).includes((error as ObservedFailure)?.code);
  const cancellationDefinition = (ref: WireRunRef, requestControl: CancellationRequestControl,
    publicationControl: CancellationPublicationControl) => {
    const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid) as StoredRunRow | undefined;
    if (row === undefined) fail('ClientCancellationDenied');
    retainedIdentity(row, requestControl);
    if (!Number.isInteger(row.revision) || row.revision < 0 || row.revision > 2147483647) {
      fail('ClientCancellationRevisionConflict');
    }
    return {row, facts: retainedRunFacts(row, publicationControl, maxRunDefinitionWireBytes, updateOriginalControl)};
  };
  const commitRunCancellation = (ref: WireRunRef, revision: number): void => {
    const changed = database.prepare(`UPDATE client_requests SET
      cancellation_requested = 1, revision = revision + 1
      WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ?
        AND revision = ? AND cancellation_requested = 0`).run(
      ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid, revision);
    if (changed.changes !== 1) fail('ClientRequestJournalCorrupt');
  };
  const cancellationIdentity = (ref: WireCancellationRef, definition: RunFacts['runDefinition'], control: CancellationRequestControl) => {
    const identity = control.clientCancellationAdmitRecord(ref.namespaceId,
      ref.authorityScopeCid, ref.cancelId, definition, ref.expectedRevision);
    if (identity === undefined) fail('ClientCancellationDenied');
    return identity;
  };
  const cancellationReadmission = (record: JournalRow, requestControl: CancellationRequestControl,
    publicationControl: CancellationPublicationControl) => {
    const cancelRef = Object.freeze({namespaceId: record.namespace_id,
      authorityScopeCid: record.authority_scope_cid,
      runDefinitionCid: record.run_definition_cid, cancelId: record.cancel_id,
      expectedRevision: record.expected_revision});
    if (!validCancellationRef(cancelRef)) fail('ClientRequestJournalCorrupt');
    const {row, facts} = cancellationDefinition(cancelRef, requestControl, publicationControl);
    const identity = cancellationIdentity(cancelRef, facts.runDefinition, requestControl);
    if (requestControl.clientCancellationIntentCid(identity) !== record.intent_fingerprint_cid) {
      fail('ClientRequestJournalCorrupt');
    }
    if (record.outcome_wire === null && record.outcome_cid === null) {
      return {identity, cancelRef, outcome: undefined};
    }
    if (typeof record.outcome_wire !== 'string' ||
        Buffer.byteLength(record.outcome_wire) > 4096 || !cid(record.outcome_cid) ||
        `sha256:${createHash('sha256').update(record.outcome_wire).digest('hex')}` !== record.outcome_cid) {
      fail('ClientRequestJournalCorrupt');
    }
    let outcome: WireCancellation;
    try { outcome = JSON.parse(record.outcome_wire) as WireCancellation; }
    catch (cause) { fail('ClientRequestJournalCorrupt', cause); }
    if (outcome === null || typeof outcome !== 'object' ||
        Object.keys(outcome).sort().join(',') !== 'cancelRef,kind,ref,revision' ||
        !['accepted', 'already_requested', 'already_terminal'].includes(outcome.kind) ||
        !Number.isInteger(outcome.revision) || outcome.revision < cancelRef.expectedRevision ||
        outcome.revision > row.revision ||
        outcome.kind !== 'already_terminal' && !facts.cancellationRequested ||
        outcome.kind === 'accepted' && outcome.revision === cancelRef.expectedRevision ||
        canonicalValueJson(outcome.cancelRef) !== canonicalValueJson(cancelRef) ||
        canonicalValueJson(outcome.ref) !== canonicalValueJson({namespaceId: cancelRef.namespaceId,
          authorityScopeCid: cancelRef.authorityScopeCid, runDefinitionCid: cancelRef.runDefinitionCid}) ||
        canonicalValueJson(outcome) !== record.outcome_wire) fail('ClientRequestJournalCorrupt');
    return {identity, cancelRef, outcome: Object.freeze({...outcome,
      ref: Object.freeze(outcome.ref), cancelRef})};
  };
  const cancellationAction = (requested: CancellationIdentity, retained: CancellationIdentity | undefined,
    facts: RunFacts, row: StoredRunRow, currentAuthorization: boolean,
    publicationCommitted: boolean, requestControl: CancellationRequestControl) => {
    const action = requestControl.clientCancellationOperationAction(requested,
      retained ?? requested, retained !== undefined, facts.runDefinition,
      Number(row.revision), currentAuthorization,
      publicationCommitted || facts.preDispatchFailureConfirmed ||
        facts.physicalCloseConfirmed && facts.observedTerminalOutcome !== null,
      facts.cancellationRequested);
    if (action === 4) rejectCancellation('ClientCancellationIntentConflict', 'conflict', 'intent');
    if (action === 6) rejectCancellation('ClientCancellationRevisionConflict', 'conflict', 'control_revision');
    if (![0, 1, 2, 3].includes(action)) fail('ClientCancellationDenied');
    return action;
  };

  return {
    // Persist the common cancellation decision under the physical-start lock.
    // The Host observes publication separately; a racing commit can still win.
    requestCancellation(ref: WireRunRef, {currentAuthorization, publicationCommitted}: CancellationAuthorization,
      requestControl: CancellationRequestControl, publicationControl: CancellationPublicationControl) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid) ||
          typeof currentAuthorization !== 'boolean' ||
          typeof publicationCommitted !== 'boolean') {
        fail('InvalidClientRunCancellation');
      }
      return transact('cancel', 'ClientRunCancellationUnknown',
        error => (error as ObservedFailure)?.code === 'ClientRunCancellationDenied', () => {
        const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid,
          ref.runDefinitionCid) as StoredRunRow | undefined;
        if (row === undefined) fail('ClientRunCancellationDenied');
        retainedIdentity(row, requestControl);
        const facts = retainedRunFacts(row, publicationControl,
          maxRunDefinitionWireBytes, updateOriginalControl);
        const action = requestControl.clientRunCancellationAction(facts.runDefinition,
          ref.runDefinitionCid, currentAuthorization,
          publicationCommitted || facts.preDispatchFailureConfirmed ||
            facts.physicalCloseConfirmed &&
              facts.observedTerminalOutcome !== null,
          facts.cancellationRequested);
        if (![0, 1, 2].includes(action)) fail('ClientRunCancellationDenied');
        const original = admission(row);
        const revision = original.revision + (action === 0 ? 1 : 0);
        if (!Number.isSafeInteger(revision)) fail('ClientRunCancellationDenied');
        if (action === 0) commitRunCancellation(original.ref, original.revision);
        return Object.freeze({ref: original.ref,
          kind: (['accepted', 'already_requested', 'already_terminal'] as const)[action],
          revision});
      });
    },
    // Persist the immutable operation before touching the Model fence journal.
    // Pending custody is unknown, not acceptance. The final outcome and Run
    // cancellation flag commit together in this existing physical owner.
    recordCancellationOperation(ref: WireRunRef, {cancelId, expectedRevision,
      currentAuthorization, publicationCommitted, modelCancellationOwner}: CancellationRecordOptions,
      requestControl: CancellationRequestControl, publicationControl: CancellationPublicationControl) {
      ensureOpen();
      const cancelRef = ownedCancellationRef({...ref, cancelId, expectedRevision});
      if (!validCancellationRef(cancelRef) || typeof currentAuthorization !== 'boolean' ||
          typeof publicationCommitted !== 'boolean') fail('InvalidClientCancellationOperation');
      if (!currentAuthorization) fail('ClientCancellationDenied');
      const pending = transact('cancel_admission', 'ClientCancellationUnknown',
        cancellationKnownFailure, () => {
          const custodyCount = assertJournalCancellationCustody(cancellationUsage, cancellationIssued);
          const {row, facts} = cancellationDefinition(ref, requestControl, publicationControl);
          const identity = cancellationIdentity(cancelRef, facts.runDefinition, requestControl);
          const record = cancellationSelect.get(ref.namespaceId, ref.authorityScopeCid, cancelId as string);
          const retained = record === undefined ? undefined :
            cancellationReadmission(record, requestControl, publicationControl);
          const action = cancellationAction(identity, retained?.identity, facts, row,
            currentAuthorization, publicationCommitted, requestControl);
          if (retained !== undefined) return {...retained, facts, action};
          if (assertJournalSubmissionCustody(requestUsage, submissionIssued) + custodyCount >= maxRecords) {
            rejectCancellation('ClientRequestJournalCapacity', 'refused', 'admission_capacity');
          }
          cancellationInsert.run(ref.namespaceId, ref.authorityScopeCid, cancelId as string,
            ref.runDefinitionCid, expectedRevision as number, requestControl.clientCancellationIntentCid(identity));
          database.prepare(`UPDATE client_cancellation_custody SET issued_count = issued_count + 1
            WHERE singleton = 1`).run();
          return {identity, cancelRef, outcome: undefined, facts, action};
        });
      if (pending.outcome !== undefined) return Object.freeze({cancellation: pending.outcome, recorded: false});
      const originalRunWire = pending.facts.runAdmissionEvidence?.modelOriginalRunWire;
      if (originalRunWire !== undefined && !publicationCommitted &&
          !pending.facts.preDispatchFailureConfirmed &&
          !(pending.facts.physicalCloseConfirmed && pending.facts.observedTerminalOutcome !== null)) {
        try {
          if (typeof modelCancellationOwner?.fenceRunCancellation !== 'function' ||
              typeof modelCancellationOwner?.modelCancellationFenced !== 'function') {
            fail('ClientCancellationModelFenceUnavailable');
          }
          // Only the checkpoint Owner can establish the fence, using the
          // retained original input rather than the current Host configuration.
          modelCancellationOwner.fenceRunCancellation({originalRunWire});
          const runId = publicationControl.runDefinitionRunId(pending.facts.runDefinition);
          if (modelCancellationOwner.modelCancellationFenced(runId, ref.runDefinitionCid) !== true) {
            fail('ClientCancellationModelFenceUnconfirmed');
          }
        } catch (cause) { fail('ClientCancellationUnknown', cause); }
      }
      return transact('cancel_commit', 'ClientCancellationUnknown', cancellationKnownFailure, () => {
        assertJournalCancellationCustody(cancellationUsage, cancellationIssued);
        const record = cancellationSelect.get(ref.namespaceId, ref.authorityScopeCid, cancelId as string);
        if (record === undefined) fail('ClientRequestJournalCorrupt');
        const retained = cancellationReadmission(record, requestControl, publicationControl);
        const {row, facts} = cancellationDefinition(ref, requestControl, publicationControl);
        cancellationAction(pending.identity, retained.identity, facts, row,
          currentAuthorization, publicationCommitted, requestControl);
        if (retained.outcome !== undefined) return Object.freeze({cancellation: retained.outcome, recorded: false});
        const action = requestControl.clientRunCancellationAction(facts.runDefinition,
          ref.runDefinitionCid, currentAuthorization,
          publicationCommitted || facts.preDispatchFailureConfirmed ||
            facts.physicalCloseConfirmed && facts.observedTerminalOutcome !== null,
          facts.cancellationRequested);
        if (![0, 1, 2].includes(action)) fail('ClientCancellationDenied');
        if (action === 0 && row.revision >= 2147483647) fail('ClientCancellationRevisionConflict');
        if (action === 0) commitRunCancellation(ref, row.revision);
        const outcome = Object.freeze({ref: admission(row).ref, cancelRef: retained.cancelRef,
          kind: (['accepted', 'already_requested', 'already_terminal'] as const)[action],
          revision: Number(row.revision) + (action === 0 ? 1 : 0)});
        const wire = canonicalValueJson(outcome);
        const checksum = `sha256:${createHash('sha256').update(wire).digest('hex')}`;
        if (database.prepare(`UPDATE client_cancellation_operations SET outcome_wire = ?, outcome_cid = ?
          WHERE namespace_id = ? AND authority_scope_cid = ? AND cancel_id = ?
            AND outcome_wire IS NULL`).run(wire, checksum, ref.namespaceId,
          ref.authorityScopeCid, cancelId as string).changes !== 1) fail('ClientRequestJournalCorrupt');
        return Object.freeze({cancellation: outcome, recorded: true});
      });
    },
    // An exact, authorized observation. It never fences, starts execution or
    // completes a pending operation; absent custody is not proof of rejection.
    lookupCancellationOperation(cancelRef: CancellationCandidate | null | undefined,
      {currentAuthorization}: Pick<CancellationAuthorization, 'currentAuthorization'>,
      requestControl: CancellationRequestControl, publicationControl: CancellationPublicationControl) {
      ensureOpen();
      if (!validCancellationRef(cancelRef) || typeof currentAuthorization !== 'boolean') {
        fail('InvalidClientCancellationLookup');
      }
      if (!currentAuthorization) fail('ClientCancellationDenied');
      return transact('cancel_lookup', 'ClientCancellationLookupUnknown', cancellationKnownFailure, () => {
        assertJournalCancellationCustody(cancellationUsage, cancellationIssued);
        const {row, facts} = cancellationDefinition(cancelRef, requestControl, publicationControl);
        const requested = cancellationIdentity(cancelRef, facts.runDefinition, requestControl);
        const record = cancellationSelect.get(cancelRef.namespaceId, cancelRef.authorityScopeCid, cancelRef.cancelId);
        if (record === undefined) return Object.freeze({kind: 'unknown' as const,
          cancelRef: ownedCancellationRef(cancelRef)});
        const retained = cancellationReadmission(record, requestControl, publicationControl);
        cancellationAction(requested, retained.identity, facts, row, currentAuthorization, false, requestControl);
        return retained.outcome === undefined ? Object.freeze({kind: 'unknown' as const, cancelRef: retained.cancelRef}) :
          Object.freeze({kind: 'found' as const, cancellation: retained.outcome});
      });
    },
  };
}
