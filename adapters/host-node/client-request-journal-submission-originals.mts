// The same original submission epoch and admitted input for a single Journal.
import {createHmac, timingSafeEqual} from 'node:crypto';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import type {WireSubmissionEpoch} from '../../packages/client-wire/index.js';
import type {createSqliteTransaction} from '../host-common/sqlite-transaction.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import {hexKey, journalIntentWireBytes, maxEpochTtlMs, validEpochAuthority,
  type snapshotJournalConfiguration} from './client-request-journal-format.mjs';
import {cid} from './client-request-journal-records.mjs';
import {fail, type JournalSqlConnection} from './client-request-journal-sql.mjs';

// Common ABI method views. The handle is forwarded to its original receiver;
// a structural type alone cannot establish an admitted original.
type CommonOriginal = Exclude<SynchronousRuntimeData, void>;
type EpochControl = Readonly<{
  clientSubmissionEpoch(scope: string, nonce: string, notBefore: number, expiresAt: number): SynchronousRuntimeData;
  clientSubmissionEpochCid(handle: CommonOriginal): string;
  clientSubmissionEpochValidity(handle: CommonOriginal, now: number): string | undefined;
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
