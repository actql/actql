// The same original submission epoch and admitted input for a single Journal.
import {createHmac, randomBytes, timingSafeEqual} from 'node:crypto';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {sameSubmissionRef, validSubmissionName, validSubmissionOutcome,
  validSubmissionRef, validStoredSubmissionOutcome} from '../../packages/client-wire/index.mjs';
import type {WireConnection, WireSubmissionEpoch, WireSubmissionOutcome, WireSubmissionRef, WireSubmissionRestart}
  from '../../packages/client-wire/index.js';
import type {createSqliteTransaction} from '../host-common/sqlite-transaction.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import {assertJournalIntentCustody, assertJournalRestartCustody, assertJournalSubmissionCustody,
  assertJournalNameCustody, authenticateJournalName, hexKey, journalIntentWireBytes, maxEpochTtlMs, validEpochAuthority,
  type snapshotJournalConfiguration} from './client-request-journal-format.mjs';
import type {createJournalAttempts} from './client-request-journal-attempts.mjs';
import {cid, text} from './client-request-journal-records.mjs';
import {fail, type JournalSqlConnection} from './client-request-journal-sql.mjs';

// Common ABI method views. The handle is forwarded to its original receiver;
// a structural type alone cannot establish an admitted original.
type CommonOriginal = Exclude<SynchronousRuntimeData, void>;
type EpochControl = Readonly<{
  clientSubmissionEpoch(scope: string, nonce: string, notBefore: number, expiresAt: number): SynchronousRuntimeData;
  clientSubmissionEpochCid(handle: CommonOriginal): string;
  clientSubmissionEpochValidity(handle: CommonOriginal, now: number):
    'admissible' | 'expired' | 'not_yet_valid' | undefined;
  clientSubmissionEpochWire(handle: CommonOriginal): string;
}>;
type IntentControl = Readonly<{
  clientSubmittedIntent(wire: string, bytes: number, nodes: number, depth: number): SynchronousRuntimeData;
  clientSubmittedIntentWire(intent: unknown): string;
  clientSubmittedIntentCid(intent: unknown): string;
}>;
type EpochCandidate = Readonly<Partial<Record<keyof WireSubmissionEpoch, unknown>>>;
type EpochFields = Readonly<{authorityScopeCid?: unknown; currentAuthorization?: unknown; purpose: string}>;
type OriginalEpoch = Readonly<{captured: WireSubmissionEpoch; handle: CommonOriginal}>;
type OriginalIntent = Readonly<{intent: unknown; wire: string; identity: string}>;
type SubmissionOperation = {
  epoch: WireSubmissionEpoch; control: object; wire: string;
  original?: OriginalEpoch; authenticationKey?: string; epochCid?: string;
  floor?: number; boundary?: 'early' | 'expired' | 'admissible'; borrowedIntentOriginal?: OriginalIntent;
};
type JournalStatement = ReturnType<JournalSqlConnection['prepare']>;
type IsSafeInteger = (value: unknown) => value is number;
type IntentBounds = Pick<ReturnType<typeof snapshotJournalConfiguration>,
  'maxInspectionBytes' | 'maxDatabaseBytes' | 'primaryExecutionLimits'>;

export function createJournalSubmissionOriginals(epochAuthority: Pick<JournalStatement, 'get'>,
  advanceEpochTime: Pick<JournalStatement, 'run'>, transaction: ReturnType<typeof createSqliteTransaction>,
  ensureOpen: () => void, submissionEpochNow: () => number, configuration: IntentBounds) {
  const {maxInspectionBytes, maxDatabaseBytes, primaryExecutionLimits} = configuration;
  const submissionOperations = new WeakMap<object, SubmissionOperation>();
  const epochClock = (operation?: SubmissionOperation, persist = true) => {
    const row = epochAuthority.get();
    if (!validEpochAuthority(row)) fail('ClientSubmissionEpochCustodyLost');
    const now = submissionEpochNow();
    if (!Number.isSafeInteger(now) || now < 0 ||
        now > Number.MAX_SAFE_INTEGER - maxEpochTtlMs) fail('ClientSubmissionEpochClockInvalid');
    const observedAt = Math.max(now, row.observed_at, operation?.floor ?? 0);
    let floor = observedAt;
    if (operation !== undefined) {
      const boundary = observedAt < operation.epoch.notBefore ? 'early' :
        observedAt >= operation.epoch.expiresAt ? 'expired' : 'admissible';
      // One durable floor belongs to this public operation, not each private
      // getter. A newly observed interval boundary still has its own durable
      // consequence. The retained row, never this memo, establishes its ACK.
      if (operation.boundary !== boundary) {
        operation.floor = Math.max(operation.floor ?? 0, observedAt);
        operation.boundary = boundary;
      }
      floor = operation.floor!;
    }
    const needsWrite = floor > row.observed_at;
    if (persist && needsWrite) advanceEpochTime.run(floor);
    return {...row, observed_at: observedAt, needsWrite};
  };
  const epochHandle = (epoch: unknown, control: EpochControl) => {
    const operation = submissionOperations.get(epoch as object);
    if (operation?.control === control && operation.original !== undefined) return operation.original;
    if (epoch === null || typeof epoch !== 'object' || Array.isArray(epoch) ||
        JSON.stringify(Object.keys(epoch).sort()) !== JSON.stringify([
          'authenticator', 'authorityScopeCid', 'epochNonce', 'expiresAt', 'notBefore', 'version',
        ])) fail('ClientSubmissionEpochUnverifiable');
    const captured = (operation?.control === control ? epoch : Object.freeze({...epoch})) as EpochCandidate;
    if (captured.version !== 'actql-submission-epoch/0.1' ||
        !cid(captured.authorityScopeCid) || !hexKey(captured.epochNonce) ||
        !(Number.isSafeInteger as IsSafeInteger)(captured.notBefore) || !(Number.isSafeInteger as IsSafeInteger)(captured.expiresAt) ||
        Object.is(captured.notBefore, -0) || Object.is(captured.expiresAt, -0) ||
        !hexKey(captured.authenticator)) fail('ClientSubmissionEpochUnverifiable');
    const handle = control.clientSubmissionEpoch(captured.authorityScopeCid,
      captured.epochNonce as string, captured.notBefore, captured.expiresAt);
    if (handle === undefined) fail('ClientSubmissionEpochUnverifiable');
    const original = {captured: captured as WireSubmissionEpoch, handle};
    if (operation?.control === control) operation.original = original;
    return original;
  };
  const authenticateEpoch = (key: string, wire: string) => createHmac('sha256',
    Buffer.from(key, 'hex')).update(wire, 'utf8').digest('hex');
  const authenticateOriginalEpoch = (epoch: unknown, control: EpochControl,
    authority: Readonly<{authentication_key: string}>, code: string) => {
    const original = epochHandle(epoch, control);
    const operation = submissionOperations.get(epoch as object);
    if (operation?.control !== control || operation.authenticationKey !== authority.authentication_key) {
      const authenticated = authenticateEpoch(authority.authentication_key,
        control.clientSubmissionEpochWire(original.handle));
      if (!timingSafeEqual(Buffer.from(authenticated, 'hex'),
        Buffer.from(original.captured.authenticator, 'hex'))) fail(code);
      if (operation?.control === control) operation.authenticationKey = authority.authentication_key;
    }
    return original;
  };
  const inspectEpoch = (epoch: unknown, {authorityScopeCid, currentAuthorization,
    purpose}: EpochFields, control: EpochControl, persist: boolean) => {
    ensureOpen();
    if (currentAuthorization !== true) fail('ClientSubmissionEpochUnauthorized');
    if (!cid(authorityScopeCid) || !['admit', 'lookup'].includes(purpose)) {
      fail('InvalidClientSubmissionEpochOperation');
    }
    const operation = submissionOperations.get(epoch as object);
    const clock = epochClock(operation?.control === control ? operation : undefined, persist);
    const {captured, handle} = authenticateOriginalEpoch(epoch, control, clock,
      'ClientSubmissionEpochUnverifiable');
    if (captured.authorityScopeCid !== authorityScopeCid) {
      fail('ClientSubmissionEpochScopeMismatch');
    }
    const validity = control.clientSubmissionEpochValidity(handle, clock.observed_at);
    if (validity === undefined) fail('ClientSubmissionEpochClockInvalid');
    if (operation?.control === control && operation.epochCid === undefined) {
      operation.epochCid = control.clientSubmissionEpochCid(handle);
    }
    return {verified: {handle, epoch: captured, validity,
      epochCid: operation?.control === control ? operation.epochCid : control.clientSubmissionEpochCid(handle)},
    needsWrite: clock.needsWrite};
  };
  const verifyEpochLocked = (epoch: unknown, fields: EpochFields, control: EpochControl) => inspectEpoch(epoch, fields, control, true).verified;
  const verifyEpoch = (epoch: unknown, fields: EpochFields, control: EpochControl) => {
    if (submissionOperations.get(epoch as object)?.control === control) {
      const observed = inspectEpoch(epoch, fields, control, false);
      if (!observed.needsWrite) return observed.verified;
    }
    return transaction.run(() => verifyEpochLocked(epoch, fields, control));
  };

  const admitIntentOriginal = (wire: unknown, control: IntentControl, epoch: unknown, code: string, canonical = true) => {
    const bytes = journalIntentWireBytes(wire, maxInspectionBytes, maxDatabaseBytes, primaryExecutionLimits);
    const operation = submissionOperations.get(epoch as object);
    const previous = operation?.control === control ? operation.borrowedIntentOriginal : undefined;
    if (previous !== undefined && previous.wire === wire) return previous;
    // Every JSON node and nesting level occupies at least one original byte.
    // No independent historical node/depth ceiling narrows this admitted wire.
    const intent = control.clientSubmittedIntent(wire as string, bytes, bytes, bytes);
    if (intent === undefined) fail(code);
    const original = {intent, wire: control.clientSubmittedIntentWire(intent),
      identity: control.clientSubmittedIntentCid(intent)};
    if (canonical && original.wire !== wire) fail(code);
    return original;
  };
  const originalIntent = (intent: unknown, control: IntentControl, epoch: unknown) => {
    const operation = submissionOperations.get(epoch as object);
    const previous = operation?.control === control ? operation.borrowedIntentOriginal : undefined;
    if (previous !== undefined && previous.intent === intent) return previous;
    const wire = control.clientSubmittedIntentWire(intent);
    const identity = control.clientSubmittedIntentCid(intent);
    const original = admitIntentOriginal(wire, control, epoch, 'InvalidClientSubmittedIntent');
    if (original.identity !== identity) fail('InvalidClientSubmittedIntent');
    return original;
  };

  // The submission adapter owns one deeply frozen snapshot per public call.
  // Only that exact epoch may reuse pure authentication and its durable
  // time floor. Current permission and the retained authority row are still
  // checked at use; releasing this scope retains no cross-operation fact.
  const retainSubmissionOperation = (epoch: unknown, control: IntentControl, borrowedIntent?: unknown) => {
    ensureOpen();
    if (epoch === undefined) return undefined;
    if (epoch === null || typeof epoch !== 'object' || !Object.isFrozen(epoch) ||
        submissionOperations.has(epoch)) fail('InvalidClientSubmissionOperation');
    const operation: SubmissionOperation = {epoch: epoch as WireSubmissionEpoch, control, wire: canonicalValueJson(epoch, {dataKeys: true})};
    // An explicit fixed preparation consumer lends this exact nominal intent
    // only until this operation's existing release, before its handler holder
    // returns. No inferred cache, cross-epoch inheritance or durable alias.
    if (borrowedIntent !== undefined) {
      const wire = control.clientSubmittedIntentWire(borrowedIntent);
      const identity = control.clientSubmittedIntentCid(borrowedIntent);
      if (typeof wire !== 'string' || typeof identity !== 'string') fail('InvalidClientSubmittedIntent');
      journalIntentWireBytes(wire, maxInspectionBytes, maxDatabaseBytes, primaryExecutionLimits);
      operation.borrowedIntentOriginal = {intent: borrowedIntent, wire, identity};
    }
    submissionOperations.set(epoch, operation);
    return () => {
      // A retained old release cannot revoke a later same-epoch operation.
      // Cut the borrowed alias even if this light release closure escapes.
      operation.borrowedIntentOriginal = undefined;
      if (submissionOperations.get(epoch) === operation) submissionOperations.delete(epoch);
    };
  };

  const restoreStoredEpoch = (originalEpoch: unknown, control: object, row: Readonly<{epoch_wire: unknown}>): unknown => {
    const operation = submissionOperations.get(originalEpoch as object);
    return operation?.control === control &&
      operation.wire === row.epoch_wire ? originalEpoch : JSON.parse(row.epoch_wire as string);
  };
  return {epochClock, epochHandle, authenticateEpoch, authenticateOriginalEpoch, verifyEpochLocked, verifyEpoch,
    admitIntentOriginal, originalIntent, restoreStoredEpoch, retainSubmissionOperation};
}

// These unchecked views describe columns from the original SQLite statements.
// The existing validation and same-original checks below admit their values.
type JournalRow = NonNullable<ReturnType<JournalStatement['get']>>;
type IntentRow = JournalRow & Readonly<{
  submission_id: string; authority_scope_cid: string; nonce: string; intent_cid: string;
  intent_wire: string; epoch_wire: string; outcome_wire: string | null;
  accepted_at: number; revision: number; phase: string;
}>;
type RestartRow = JournalRow & Readonly<{
  link_wire: string; original_submission_id: string; fresh_submission_id: string;
}>;
type StoredRestart = WireSubmissionRestart & Readonly<{
  freshSubmissionRef: WireSubmissionRef; intentCid: string; actorId: string;
}>;
type RestartCandidate = Readonly<Partial<Record<keyof WireSubmissionRestart, unknown>>>;
type BoundSubmission = WireSubmissionRef & Readonly<{currentAuthorization: unknown; intentCid?: string}>;
type EpochAuthority = Readonly<{authorityScopeCid: string; currentAuthorization: unknown}>;
type IntentAdmission = EpochAuthority & Readonly<{phase?: string; outcome?: unknown}>;
type IntentCustody = ReturnType<typeof assertJournalIntentCustody>;
type ReadyOutcome = Extract<WireSubmissionOutcome, {kind: 'ready'}>;
type RetainedSubmissionControl = EpochControl & IntentControl & Readonly<{
  clientSubmissionRequestId(handle: CommonOriginal, nonce: string): string | undefined;
  clientSubmittedIntentTransition(previous: string, next: string): boolean;
  clientSubmittedIntentObservation(expected: unknown, original: unknown, phase: string, inserted: boolean): string | undefined;
}>;
type RetainedIntent = Readonly<{
  intent: unknown; row: IntentRow; authenticationKey: string; restartRow: RestartRow | undefined;
  value: Readonly<{
    submissionRef: WireSubmissionRef; requestId: string; intentCid: string; intentWire: string;
    phase: string; revision: number; outcome: WireSubmissionOutcome | undefined;
    unresolvedHistory?: StoredRestart; observation?: string;
  }>;
}>;
type SubmissionReceipt = RetainedIntent['value'] & Readonly<{inserted: boolean}>;
type IntentStatements = Readonly<{
  epochAuthority: JournalStatement; requestUsage: JournalStatement; submissionIssued: JournalStatement;
  intentSelect: JournalStatement; intentUsage: JournalStatement; intentIssued: JournalStatement; intentRetired: JournalStatement;
  restartSelect: JournalStatement; restartUsage: JournalStatement; restartIssued: JournalStatement;
  nameSelect: Pick<JournalStatement, 'get'>; nameCustody: JournalStatement;
}>;
type SubmissionNameRow = JournalRow & Readonly<{submission_id: string}>;
type NamedIntentAdmission = Readonly<{
  namespaceId: unknown; actorId: unknown; authorityScopeCid: unknown; currentAuthorization: unknown;
  submissionRef?: WireSubmissionRef | null;
}>;
type CheckedIntentAdmission = EpochAuthority & Readonly<{
  unresolvedHistory?: RestartCandidate | null; actorId?: unknown;
}>;
type RecordedIntentAdmission = IntentAdmission & CheckedIntentAdmission & Readonly<{outcome?: WireSubmissionOutcome}>;
type IntentRevision = EpochAuthority & Readonly<{expectedRevision: number}>;
type CompletedIntentAdmission = IntentRevision & Readonly<{connection: WireConnection}>;
type SubmissionAttempts = Pick<ReturnType<typeof createJournalAttempts>,
  'rejectSubmission' | 'submissionTransaction' | 'rejectSubmissionEpoch'>;

export function createJournalSubmissionRows(database: JournalSqlConnection, select: Pick<JournalStatement, 'get'>,
  {epochAuthority, requestUsage, submissionIssued, intentSelect, intentUsage, intentIssued, intentRetired,
    restartSelect, restartUsage, restartIssued, nameSelect, nameCustody}: IntentStatements,
  originals: ReturnType<typeof createJournalSubmissionOriginals>, transaction: ReturnType<typeof createSqliteTransaction>,
  ensureOpen: () => void,
  {rejectSubmission, submissionTransaction, rejectSubmissionEpoch}: SubmissionAttempts,
  {inspectionBytes, maxRecords, submissionEpochTtlMs}: Pick<ReturnType<typeof snapshotJournalConfiguration>,
    'inspectionBytes' | 'maxRecords' | 'submissionEpochTtlMs'>) {
  const {authenticateEpoch, authenticateOriginalEpoch, epochClock, epochHandle, verifyEpochLocked, verifyEpoch,
    admitIntentOriginal, originalIntent, restoreStoredEpoch} = originals;
  const checkSubmissionBinding = (fields: Readonly<{authorityScopeCid: string; requestId: string}>,
    submission: BoundSubmission | undefined, control: RetainedSubmissionControl, locked = false) => {
    if (submission === undefined) return 'admissible';
    const verify = locked ? verifyEpochLocked : verifyEpoch;
    const verified = verify(submission.epoch, {authorityScopeCid: fields.authorityScopeCid,
      currentAuthorization: submission.currentAuthorization, purpose: 'admit'}, control);
    const requestId = control.clientSubmissionRequestId(verified.handle, submission.nonce);
    if (requestId === undefined) fail('InvalidClientSubmissionNonce');
    if (requestId !== fields.requestId) fail('ClientSubmissionIdentityMismatch');
    if (submission.intentCid !== undefined) {
      // Expiry stops new admission, not preparation of an already accepted
      // intent. The persisted receipt, rather than a caller flag, supplies
      // this fact. Rejection and failed preparation cannot acquire a Run.
      assertJournalIntentCustody(intentUsage, intentIssued, intentRetired, inspectionBytes);
      const row = intentSelect.get(requestId);
      if (row === undefined) fail('ClientSubmittedIntentCustodyLost');
      const retained = retainedIntent(row as IntentRow, control, submission.epoch);
      if (retained.intentCid !== submission.intentCid ||
          !['preparing', 'held', 'ready'].includes(retained.phase)) {
        fail('ClientSubmittedIntentConflict');
      }
      return 'admissible';
    }
    return verified.validity;
  };
  const refuseEpoch = (validity: string) => {
    if (validity !== 'admissible') fail(validity === 'expired'
      ? 'ClientSubmissionEpochExpired' : 'ClientSubmissionEpochNotYetValid');
  };
  // The caller must already hold this journal's transaction. Both ordinary
  // epoch admission and named resolution use this same custody transition.
  const recordIntentLocked = (submissionRef: WireSubmissionRef, original: OriginalIntent, {authorityScopeCid,
    currentAuthorization, phase = 'preparing', outcome}: IntentAdmission, restartWire: string | undefined,
    requestId: string, control: RetainedSubmissionControl, originalCustody?: IntentCustody) => {
    const retained = originalCustody ?? assertJournalIntentCustody(intentUsage, intentIssued, intentRetired, inspectionBytes);
    const existing = intentSelect.get(requestId);
    if (existing !== undefined) {
      const previous = retainedIntent(existing as IntentRow, control, submissionRef.epoch, original.intent);
      if (previous.observation === 'conflict') rejectSubmission('ClientSubmittedIntentConflict', 'conflict', 'intent');
      if (restartSelect.get(requestId)?.link_wire !== restartWire) rejectSubmission('ClientSubmissionRestartConflict', 'conflict', 'restart_decision');
      return {inserted: false, ...previous};
    }
    const current = verifyEpochLocked(submissionRef.epoch, {authorityScopeCid,
      currentAuthorization, purpose: 'admit'}, control);
    if (current.validity !== 'admissible') return {epochRejected: current.validity};
    const {restarts, originalRequestId} = checkRestartLocked(requestId, restartWire,
      {authorityScopeCid, currentAuthorization}, control);
    const intentBytes = Buffer.byteLength(original.wire);
    // Both retained purposes consume the SAME selected parent before any bind.
    // Subtraction avoids overflow and neither refunds history nor grants memory.
    if (retained.n >= maxRecords || retained.issued === Number.MAX_SAFE_INTEGER ||
        retained.bytes > inspectionBytes - restarts.bytes ||
        intentBytes > inspectionBytes - retained.bytes - restarts.bytes) {
      rejectSubmission('ClientSubmittedIntentCapacity', 'refused', 'admission_capacity');
    }
    if (restartWire !== undefined && Buffer.byteLength(restartWire) >
        inspectionBytes - retained.bytes - restarts.bytes - intentBytes) {
      fail('ClientSubmissionRestartCapacity');
    }
    database.prepare(`INSERT INTO client_submitted_intents VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)`)
      .run(requestId, authorityScopeCid, submissionRef.nonce,
        canonicalValueJson(current.epoch, {dataKeys: true}), original.identity,
        original.wire, epochAuthority.get()!.observed_at as number, phase,
        outcome === undefined ? null : canonicalValueJson(outcome, {dataKeys: true}));
    if (Number(database.prepare(`UPDATE client_submitted_intent_custody
      SET issued_count = issued_count + 1 WHERE singleton = 1 AND issued_count = ?`)
      .run(retained.issued).changes) !== 1) fail('ClientSubmittedIntentCustodyLost');
    if (restartWire !== undefined) {
      database.prepare('INSERT INTO client_submission_restarts VALUES (?, ?, ?)')
        .run(requestId, originalRequestId!, restartWire);
      if (Number(database.prepare(`UPDATE client_submission_restart_custody
        SET issued_count = issued_count + 1 WHERE singleton = 1 AND issued_count = ?`)
        .run(restarts.n).changes) !== 1) fail('ClientSubmissionRestartCustodyLost');
    }
    return {inserted: true, ...retainedIntent(intentSelect.get(requestId) as IntentRow, control,
      submissionRef.epoch, original.intent, true)};
  };
  const restartDecision = (submissionRef: unknown, intentCid: unknown,
    unresolvedHistory: RestartCandidate | null | undefined, actorId: unknown) => {
    if (unresolvedHistory === undefined) return undefined;
    if (unresolvedHistory === null || typeof unresolvedHistory !== 'object' ||
        JSON.stringify(Object.keys(unresolvedHistory).sort()) !== JSON.stringify(['acknowledgement', 'submissionRef']) ||
        unresolvedHistory.acknowledgement !== 'possible_prior_execution_and_effects' || !text(actorId)) {
      fail('InvalidClientSubmissionRestart');
    }
    return canonicalValueJson({submissionRef: unresolvedHistory.submissionRef,
      acknowledgement: unresolvedHistory.acknowledgement, freshSubmissionRef: submissionRef,
      intentCid, actorId}, {dataKeys: true});
  };
  const checkRestartLocked = (requestId: string, restartWire: string | undefined,
    fields: EpochAuthority, control: RetainedSubmissionControl) => {
    const restarts = assertJournalRestartCustody(restartUsage, restartIssued, inspectionBytes);
    if (restartWire === undefined) return {restarts};
    const restart = JSON.parse(restartWire) as StoredRestart;
    assertJournalSubmissionCustody(requestUsage, submissionIssued);
    const prior = verifyEpochLocked(restart.submissionRef.epoch,
      {...fields, purpose: 'lookup'}, control);
    const originalRequestId = control.clientSubmissionRequestId(prior.handle, restart.submissionRef.nonce);
    if (originalRequestId === undefined) fail('InvalidClientSubmissionRestart');
    if (prior.validity !== 'expired' || intentSelect.get(originalRequestId) !== undefined) {
      fail('ClientSubmissionRestartOriginalResolvable');
    }
    if (restart.submissionRef.epoch.expiresAt >= restart.freshSubmissionRef.epoch.expiresAt) {
      fail('InvalidClientSubmissionRestart');
    }
    // Unknown old execution is not a new-work permit. This connection cannot
    // discharge an existing Run/Model/Effect owner's unresolved responsibility.
    if (select.get(fields.authorityScopeCid, originalRequestId) !== undefined) {
      fail('ClientSubmissionRestartRequiresReconciliation');
    }
    if (restartSelect.get(requestId) !== undefined) fail('ClientSubmissionRestartConflict');
    if (restarts.n >= maxRecords || restarts.n === Number.MAX_SAFE_INTEGER) {
      fail('ClientSubmissionRestartCapacity');
    }
    return {restarts, originalRequestId};
  };
  const retainedRestart = (row: RestartRow | undefined, control: RetainedSubmissionControl) => {
    if (row === undefined) return undefined;
    let link: StoredRestart;
    try {link = JSON.parse(row.link_wire) as StoredRestart;} catch (cause) {fail('ClientSubmissionRestartCorrupt', cause);}
    let canonical;
    try {
      canonical = restartDecision(link?.freshSubmissionRef, link?.intentCid,
        {submissionRef: link?.submissionRef, acknowledgement: link?.acknowledgement}, link?.actorId);
    } catch (cause) {fail('ClientSubmissionRestartCorrupt', cause);}
    if (link === null || typeof link !== 'object' ||
        JSON.stringify(Object.keys(link).sort()) !== JSON.stringify([
          'acknowledgement', 'actorId', 'freshSubmissionRef', 'intentCid', 'submissionRef']) ||
        !cid(link.intentCid) || canonical !== row.link_wire) {
      fail('ClientSubmissionRestartCorrupt');
    }
    const admitRef = (ref: WireSubmissionRef) => {
      if (ref === null || typeof ref !== 'object' ||
          JSON.stringify(Object.keys(ref).sort()) !== JSON.stringify(['epoch', 'nonce'])) {
        fail('ClientSubmissionRestartCorrupt');
      }
      const {handle} = epochHandle(ref.epoch, control);
      const authority = epochAuthority.get();
      if (!validEpochAuthority(authority) ||
          authenticateEpoch(authority.authentication_key, control.clientSubmissionEpochWire(handle)) !== ref.epoch.authenticator) {
        fail('ClientSubmissionRestartCorrupt');
      }
      return control.clientSubmissionRequestId(handle, ref.nonce);
    };
    if (admitRef(link.submissionRef) !== row.original_submission_id ||
        admitRef(link.freshSubmissionRef) !== row.fresh_submission_id ||
        link.submissionRef.epoch.authorityScopeCid !== link.freshSubmissionRef.epoch.authorityScopeCid ||
        link.submissionRef.epoch.expiresAt >= link.freshSubmissionRef.epoch.expiresAt) {
      fail('ClientSubmissionRestartCorrupt');
    }
    Object.freeze(link.submissionRef.epoch); Object.freeze(link.submissionRef);
    Object.freeze(link.freshSubmissionRef.epoch); Object.freeze(link.freshSubmissionRef);
    return Object.freeze(link);
  };
  const retainedIntentOriginal = (row: IntentRow, control: RetainedSubmissionControl, originalEpoch: unknown,
    previous?: RetainedIntent, expected?: unknown, inserted = false): RetainedIntent => {
    const authority = epochAuthority.get();
    const restartRow = restartSelect.get(row.submission_id) as RestartRow | undefined;
    if (previous !== undefined && expected === undefined && validEpochAuthority(authority) &&
        authority.authentication_key === previous.authenticationKey &&
        Object.keys(row).length === Object.keys(previous.row).length &&
        Object.keys(row).every(key => row[key] === previous.row[key]) &&
        (restartRow === undefined && previous.restartRow === undefined ||
         restartRow !== undefined && previous.restartRow !== undefined &&
         Object.keys(restartRow).length === Object.keys(previous.restartRow).length &&
         Object.keys(restartRow).every(key => restartRow[key] === previous.restartRow![key]))) {
      assertJournalRestartCustody(restartUsage, restartIssued, inspectionBytes);
      return previous;
    }
    const original = admitIntentOriginal(row.intent_wire, control, originalEpoch,
      'ClientSubmittedIntentCorrupt');
    if (original.identity !== row.intent_cid) fail('ClientSubmittedIntentCorrupt');
    const intent = original.intent;
    const epoch = restoreStoredEpoch(originalEpoch, control, row) as WireSubmissionEpoch;
    if (!validEpochAuthority(authority)) fail('ClientSubmissionEpochCustodyLost');
    const {handle} = authenticateOriginalEpoch(epoch, control, authority, 'ClientSubmittedIntentCorrupt');
    if (control.clientSubmissionRequestId(handle, row.nonce) !== row.submission_id ||
        epoch.authorityScopeCid !== row.authority_scope_cid ||
        !Number.isSafeInteger(row.accepted_at) || row.accepted_at < epoch.notBefore ||
        row.accepted_at >= epoch.expiresAt || !Number.isSafeInteger(row.revision) || row.revision < 0 ||
        !control.clientSubmittedIntentTransition(row.phase, row.phase)) fail('ClientSubmittedIntentCorrupt');
    const submissionRef = Object.freeze({epoch: Object.freeze(epoch), nonce: row.nonce});
    const outcome = row.outcome_wire === null ? undefined : JSON.parse(row.outcome_wire) as WireSubmissionOutcome;
    if (outcome === undefined && row.phase !== 'preparing' ||
        outcome !== undefined && (outcome.kind !== row.phase ||
          !validStoredSubmissionOutcome(outcome, submissionRef, row.intent_cid))) {
      fail('ClientSubmittedIntentCorrupt');
    }
    if (row.phase === 'ready') {
      const run = select.get(row.authority_scope_cid, row.submission_id);
      if (run === undefined || run.run_definition_cid !== (outcome as ReadyOutcome).admission.ref.runDefinitionCid ||
          run.namespace_id !== (outcome as ReadyOutcome).admission.ref.namespaceId) fail('ClientSubmittedIntentCorrupt');
    }
    assertJournalRestartCustody(restartUsage, restartIssued, inspectionBytes);
    const unresolvedHistory = retainedRestart(restartRow, control);
    if (unresolvedHistory !== undefined && unresolvedHistory.intentCid !== row.intent_cid) {
      fail('ClientSubmissionRestartCorrupt');
    }
    const observation = expected === undefined ? undefined :
      control.clientSubmittedIntentObservation(expected, intent, row.phase, inserted);
    if (expected !== undefined && observation === undefined) fail('ClientSubmittedIntentCorrupt');
    const value = Object.freeze({submissionRef: Object.freeze({epoch: Object.freeze(epoch), nonce: row.nonce}),
      requestId: row.submission_id, intentCid: row.intent_cid, intentWire: row.intent_wire,
      phase: row.phase, revision: row.revision, outcome,
      ...(unresolvedHistory === undefined ? {} : {unresolvedHistory}),
      ...(observation === undefined ? {} : {observation})});
    return Object.freeze({intent, value, row: Object.freeze({...row}),
      authenticationKey: authority.authentication_key,
      restartRow: restartRow === undefined ? undefined : Object.freeze({...restartRow})});
  };
  const retainedIntent = (row: IntentRow, control: RetainedSubmissionControl, originalEpoch: unknown,
    expected?: unknown, inserted = false) =>
    retainedIntentOriginal(row, control, originalEpoch, undefined, expected, inserted).value;
  const methods = {
    // Intent custody is separate from Run-definition custody. A preparing
    // receipt contains no invented execution CID and performs no dispatch.
    resolveOrBindSubmittedName(name: unknown, intent: unknown, {namespaceId, actorId, authorityScopeCid,
      currentAuthorization, submissionRef}: NamedIntentAdmission, control: RetainedSubmissionControl) {
      ensureOpen();
      if (!validSubmissionName(name) || !text(namespaceId) ||
          !namespaceId.isWellFormed() || !text(actorId) || !actorId.isWellFormed() ||
          !cid(authorityScopeCid)) fail('InvalidClientSubmissionName');
      if (currentAuthorization !== true) fail('ClientSubmissionEpochUnauthorized');
      const original = originalIntent(intent, control, submissionRef?.epoch);
      const result = submissionTransaction(() => {
        const issued = assertJournalNameCustody(nameCustody);
        const intentCustody = assertJournalIntentCustody(intentUsage, intentIssued, intentRetired, inspectionBytes);
        const existing = nameSelect.get(namespaceId, actorId, name) as SubmissionNameRow | undefined;
        if (existing !== undefined) {
          if (!hexKey(existing.binding_authenticator) ||
              !timingSafeEqual(Buffer.from(existing.binding_authenticator as string, 'hex'),
                Buffer.from(authenticateJournalName(existing, epochAuthority), 'hex'))) fail('ClientSubmissionNameCustodyLost');
          if (existing.authority_scope_cid !== authorityScopeCid ||
              existing.intent_cid !== original.identity) rejectSubmission('ClientSubmittedIntentConflict', 'conflict', 'intent');
          const row = intentSelect.get(existing.submission_id);
          // Formal retirement leaves this permanent bounded fence. Missing
          // history is never promoted to an unused name or a fresh epoch.
          if (row === undefined) fail('ClientSubmissionNameUnresolvable');
          const retained = retainedIntent(row as IntentRow, control, submissionRef?.epoch);
          if (retained.requestId !== existing.submission_id ||
              retained.intentCid !== existing.intent_cid || retained.intentWire !== original.wire ||
              retained.submissionRef.epoch.authorityScopeCid !== authorityScopeCid) {
            fail('ClientSubmissionNameCustodyLost');
          }
          verifyEpochLocked(retained.submissionRef.epoch, {authorityScopeCid,
            currentAuthorization, purpose: 'lookup'}, control);
          return {inserted: false, ...retained};
        }
        if (issued >= maxRecords || issued === Number.MAX_SAFE_INTEGER) {
          rejectSubmission('ClientSubmissionNameCapacity', 'refused', 'admission_capacity');
        }
        if (!validSubmissionRef(submissionRef)) fail('InvalidClientSubmissionName');
        const verified = verifyEpochLocked(submissionRef.epoch, {authorityScopeCid,
          currentAuthorization, purpose: 'admit'}, control);
        if (verified.validity !== 'admissible') return {epochRejected: verified.validity};
        const requestId = control.clientSubmissionRequestId(verified.handle, submissionRef.nonce);
        if (requestId === undefined) fail('InvalidClientSubmissionNonce');
        // A caller-selected old nonce is not retroactively named. Only an
        // unused authenticated reference can acquire this new name and intent.
        if (intentSelect.get(requestId) !== undefined) fail('ClientSubmissionNameReferenceUsed');
        const retained = recordIntentLocked(submissionRef, original,
          {authorityScopeCid, currentAuthorization}, undefined, requestId, control, intentCustody);
        if (retained.epochRejected !== undefined) return retained;
        const row = {namespace_id: namespaceId, actor_id: actorId, name,
          authority_scope_cid: authorityScopeCid, submission_id: requestId, intent_cid: original.identity};
        database.prepare('INSERT INTO client_submission_names VALUES (?, ?, ?, ?, ?, ?, ?)')
          .run(namespaceId, actorId, name, authorityScopeCid, requestId,
            original.identity, authenticateJournalName(row, epochAuthority));
        if (Number(database.prepare(`UPDATE client_submission_name_custody
          SET issued_count = issued_count + 1 WHERE singleton = 1 AND issued_count = ?`)
          .run(issued).changes) !== 1) fail('ClientSubmissionNameCustodyLost');
        assertJournalNameCustody(nameCustody);
        return retained;
      });
      if (result.epochRejected !== undefined) rejectSubmissionEpoch(result.epochRejected);
      return Object.freeze(result as SubmissionReceipt);
    },
    checkSubmittedIntent(submissionRef: WireSubmissionRef, intent: unknown, {authorityScopeCid,
      currentAuthorization, unresolvedHistory, actorId}: CheckedIntentAdmission, control: RetainedSubmissionControl) {
      ensureOpen();
      const original = originalIntent(intent, control, submissionRef.epoch);
      const restartWire = restartDecision(submissionRef, original.identity, unresolvedHistory, actorId);
      const fields = {authorityScopeCid, currentAuthorization};
      const result = submissionTransaction(() => {
        assertJournalIntentCustody(intentUsage, intentIssued, intentRetired, inspectionBytes);
        const verified = verifyEpochLocked(submissionRef.epoch, {...fields, purpose: 'lookup'}, control);
        const requestId = control.clientSubmissionRequestId(verified.handle, submissionRef.nonce);
        if (requestId === undefined) fail('InvalidClientSubmittedIntent');
        const existing = intentSelect.get(requestId);
        if (existing !== undefined) {
          const previous = retainedIntent(existing as IntentRow, control, submissionRef.epoch);
          if (previous.intentCid !== original.identity) rejectSubmission('ClientSubmittedIntentConflict', 'conflict', 'intent');
          if (restartSelect.get(requestId)?.link_wire !== restartWire) rejectSubmission('ClientSubmissionRestartConflict', 'conflict', 'restart_decision');
        } else {
          if (verified.validity !== 'admissible') return {epochRejected: verified.validity};
          checkRestartLocked(requestId, restartWire, fields, control);
        }
        return {requestId};
      });
      if (result.epochRejected !== undefined) rejectSubmissionEpoch(result.epochRejected);
      return Object.freeze(result as Readonly<{requestId: string}>);
    },
    recordSubmittedIntent(submissionRef: WireSubmissionRef, intent: unknown, {authorityScopeCid,
      currentAuthorization, phase = 'preparing', outcome, unresolvedHistory, actorId}: RecordedIntentAdmission,
    control: RetainedSubmissionControl) {
      ensureOpen();
      const original = originalIntent(intent, control, submissionRef.epoch);
      const verified = verifyEpoch(submissionRef.epoch, {authorityScopeCid,
        currentAuthorization, purpose: 'admit'}, control);
      const requestId = control.clientSubmissionRequestId(verified.handle, submissionRef.nonce);
      const restartWire = restartDecision(submissionRef, original.identity, unresolvedHistory, actorId);
      if (requestId === undefined || !['preparing', 'not_accepted'].includes(phase)) {
        fail('InvalidClientSubmittedIntent');
      }
      if (phase === 'not_accepted' && (outcome?.kind !== phase ||
          !validStoredSubmissionOutcome(outcome, submissionRef, original.identity))) {
        fail('InvalidClientSubmittedIntentOutcome');
      }
      if (phase === 'preparing' && outcome !== undefined && (outcome.kind !== phase ||
          !validStoredSubmissionOutcome(outcome, submissionRef, original.identity))) {
        fail('InvalidClientSubmittedIntentOutcome');
      }
      const result = submissionTransaction(() => recordIntentLocked(submissionRef, original,
        {authorityScopeCid, currentAuthorization, phase, outcome}, restartWire, requestId, control));
      if (result.epochRejected !== undefined) rejectSubmissionEpoch(result.epochRejected);
      return Object.freeze(result as SubmissionReceipt);
    },
    lookupSubmittedIntent(submissionRef: WireSubmissionRef, {authorityScopeCid, currentAuthorization}: EpochAuthority,
    control: RetainedSubmissionControl, expected?: unknown) {
      ensureOpen();
      const verified = verifyEpoch(submissionRef.epoch, {authorityScopeCid,
        currentAuthorization, purpose: 'lookup'}, control);
      const requestId = control.clientSubmissionRequestId(verified.handle, submissionRef.nonce);
      if (requestId === undefined) fail('InvalidClientSubmissionNonce');
      const row = intentSelect.get(requestId);
      return row === undefined ? undefined : retainedIntent(row as IntentRow, control, submissionRef.epoch, expected);
    },
    // Explicit trusted-Host retention operation, not a Client cancellation
    // or evidence of nonexecution. In-progress and Run-connected custody stays
    // with its existing owners. No automatic eviction during new admission.
    retireSubmittedIntent(submissionRef: WireSubmissionRef, {authorityScopeCid, currentAuthorization,
      expectedRevision}: IntentRevision, control: RetainedSubmissionControl) {
      ensureOpen();
      const fields = {authorityScopeCid, currentAuthorization, purpose: 'lookup'};
      const verified = verifyEpoch(submissionRef.epoch, fields, control);
      const requestId = control.clientSubmissionRequestId(verified.handle, submissionRef.nonce);
      if (requestId === undefined || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
        fail('InvalidClientSubmittedIntentRetirement');
      }
      return Object.freeze(transaction.run(() => {
        const custody = assertJournalIntentCustody(intentUsage, intentIssued, intentRetired, inspectionBytes);
        const current = verifyEpochLocked(submissionRef.epoch, fields, control);
        if (current.validity !== 'expired') fail('ClientSubmittedIntentNotRetirable');
        const row = intentSelect.get(requestId);
        if (row === undefined) return {retired: false};
        const original = retainedIntent(row as IntentRow, control, submissionRef.epoch);
        if (original.revision !== expectedRevision) fail('ClientSubmittedIntentRetirementConflict');
        if (!['not_accepted', 'preparation_failed'].includes(original.phase) ||
            select.get(authorityScopeCid, requestId) !== undefined) {
          fail('ClientSubmittedIntentNotRetirable');
        }
        if (Number(database.prepare(`DELETE FROM client_submitted_intents
          WHERE submission_id = ? AND revision = ?`).run(requestId, expectedRevision).changes) !== 1 ||
            Number(database.prepare(`UPDATE client_submitted_intent_retirement
              SET retired_count = retired_count + 1 WHERE singleton = 1 AND retired_count = ?`)
              .run(custody.retired).changes) !== 1) fail('ClientSubmittedIntentCustodyLost');
        return {retired: true};
      }));
    },
    completeSubmittedIntent(submissionRef: WireSubmissionRef, outcome: unknown, {authorityScopeCid,
      currentAuthorization, expectedRevision, connection}: CompletedIntentAdmission, control: RetainedSubmissionControl) {
      ensureOpen();
      const verified = verifyEpoch(submissionRef.epoch, {authorityScopeCid,
        currentAuthorization, purpose: 'lookup'}, control);
      const requestId = control.clientSubmissionRequestId(verified.handle, submissionRef.nonce);
      if (requestId === undefined || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
        fail('InvalidClientSubmittedIntentOutcome');
      }
      return transaction.run(() => {
        assertJournalIntentCustody(intentUsage, intentIssued, intentRetired, inspectionBytes);
        const row = intentSelect.get(requestId);
        if (row === undefined) fail('ClientSubmittedIntentCustodyLost');
        const retained = retainedIntent(row as IntentRow, control, submissionRef.epoch);
        if (!sameSubmissionRef(retained.submissionRef, submissionRef) ||
            !validSubmissionOutcome(outcome, connection, submissionRef, retained.intentCid)) {
          fail('InvalidClientSubmittedIntentOutcome');
        }
        if (retained.revision !== expectedRevision) return retained;
        if (!control.clientSubmittedIntentTransition(retained.phase, outcome.kind)) {
          fail('InvalidClientSubmittedIntentOutcome');
        }
        if (['ready', 'not_accepted', 'preparation_failed'].includes(retained.phase)) return retained;
        if (outcome.kind === 'ready') {
          const run = select.get(authorityScopeCid, requestId);
          if (run === undefined || run.run_definition_cid !== outcome.admission.ref.runDefinitionCid ||
              run.namespace_id !== outcome.admission.ref.namespaceId) fail('InvalidClientSubmittedIntentOutcome');
        }
        database.prepare(`UPDATE client_submitted_intents SET phase = ?, outcome_wire = ?, revision = revision + 1
          WHERE submission_id = ? AND revision = ?`).run(outcome.kind,
          canonicalValueJson(outcome, {dataKeys: true}), requestId, expectedRevision);
        return retainedIntent(intentSelect.get(requestId) as IntentRow, control, submissionRef.epoch);
      });
    },
    issueSubmissionEpoch({authorityScopeCid, currentAuthorization}: Pick<EpochFields, 'authorityScopeCid' | 'currentAuthorization'>,
    control: EpochControl) {
      ensureOpen();
      if (currentAuthorization !== true) fail('ClientSubmissionEpochUnauthorized');
      if (!cid(authorityScopeCid)) fail('InvalidClientSubmissionEpochOperation');
      return transaction.run(() => {
        const clock = epochClock();
        const epoch = {version: 'actql-submission-epoch/0.1' as const, authorityScopeCid,
          epochNonce: randomBytes(32).toString('hex'), notBefore: clock.observed_at,
          expiresAt: clock.observed_at + submissionEpochTtlMs};
        const handle = control.clientSubmissionEpoch(authorityScopeCid,
          epoch.epochNonce, epoch.notBefore, epoch.expiresAt);
        if (handle === undefined) fail('InvalidClientSubmissionEpochOperation');
        return Object.freeze({...epoch, authenticator: authenticateEpoch(
          clock.authentication_key, control.clientSubmissionEpochWire(handle))});
      });
    },
    verifySubmissionEpoch(epoch: unknown, fields: EpochFields, control: EpochControl) {
      const {handle: _handle, ...verified} = verifyEpoch(epoch, fields, control);
      return Object.freeze(verified);
    },
    submissionIdentity(epoch: unknown, nonce: string, fields: EpochFields, control: RetainedSubmissionControl) {
      const {handle, ...verified} = verifyEpoch(epoch, fields, control);
      const requestId = control.clientSubmissionRequestId(handle, nonce);
      if (requestId === undefined) fail('InvalidClientSubmissionNonce');
      return Object.freeze({...verified, requestId});
    },
  };
  return {checkSubmissionBinding, refuseEpoch, retainedIntentOriginal, retainedIntent, methods};
}
