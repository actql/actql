// The Checkpoint's held request index is advisory. Recovery still reads the
// original retained Evidence before it reconstructs authorization or presents
// the same held request. Neither lookup issues a Run or replays its read.
import {open as openFile, readFile, rename} from 'node:fs/promises';
import {join} from 'node:path';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {capturedValueCid, fail, occurrenceIdentity, occurrenceKey, pluralCapture}
  from './client-checkpoint-admission-inputs.mjs';

import type {CapturedOccurrence, SourceCapture} from './client-checkpoint-admission-inputs.mjs';
import type {CapturedRequest, createHeldCheckpointDeferrals} from './client-checkpoint-held-deferral.mjs';
import type {openContinuationEvidence} from './local-continuation-evidence.mjs';
import type {openSqliteCheckpointJournal} from './sqlite-checkpoint-journal.mjs';

type Journal = ReturnType<typeof openSqliteCheckpointJournal>;
type Continuation = Readonly<{
  boundary: string; invocation_cid: string; prepare_attempt_id: string;
  acquisition_occurrence?: ReturnType<typeof occurrenceIdentity>;
  earlier_approvals?: readonly string[];
  evidence: readonly Readonly<{name: string; semantic_cid: string}>[];
}>;
type Invocation = Readonly<{captured_submission_cid: string; request_cid: string}>;
type InvocationRequest = Readonly<{subject_cid: string; subject: Readonly<{logical_request_scope_cid: string}>}>;
type ReadApprovalOptions = Readonly<{checkpointCid?: string; earlier?: readonly string[]; prepareAttemptId?: string}>;
type Ports = ReturnType<typeof createCheckpointHeldIndex> & Readonly<{
  journal: Pick<Journal, 'inspect' | 'getPreparation' | 'expire'>;
  evidence: Pick<ReturnType<typeof openContinuationEvidence>, 'open'>;
  acquisitionIntent: ReturnType<typeof createHeldCheckpointDeferrals>['acquisitionIntent'];
  captureInventory(captured: SourceCapture): readonly CapturedOccurrence[];
  now(): number;
}>;

const LOOKUP_RETENTION_MS = 7 * 24 * 60 * 60 * 1000;

export function createCheckpointHeldIndex(heldIndex: string) {
  const indexPath = (id: string) => join(heldIndex, `${id}.json`);
  // The request ID of a held prepare attempt (not private: lookups are keyed
  // by it), written durably (file and directory) before its Checkpoint is
  // persisted. It is only an index: a missing or unreadable entry is
  // rebuilt from the attempt's captured submission.
  const syncDirectory = async (path: string) => {
    const handle = await openFile(path, 'r');
    try { await handle.sync(); } finally { await handle.close(); }
  };
  async function recordHeld(prepareAttemptId: string, requestId: string) {
    const temporary = `${indexPath(prepareAttemptId)}.${process.pid}.tmp`;
    const handle = await openFile(temporary, 'w', 0o600);
    try {
      await handle.writeFile(JSON.stringify({version:
        'actql-remote-held-request/0.1', prepare_attempt_id: prepareAttemptId,
      request_id: requestId}));
      await handle.sync();
    } finally { await handle.close(); }
    await rename(temporary, indexPath(prepareAttemptId));
    await syncDirectory(heldIndex);
  }
  async function indexedRequestId(prepareAttemptId: string) {
    try {
      const record = JSON.parse(await readFile(indexPath(prepareAttemptId),
        'utf8')) as Readonly<{prepare_attempt_id?: unknown; request_id?: unknown}>;
      return record.prepare_attempt_id === prepareAttemptId &&
        typeof record.request_id === 'string' ? record.request_id : undefined;
    } catch { return undefined; }
  }

  return {recordHeld, indexedRequestId};
}

export function createCheckpointHeldRecovery({captureInventory, evidence,
  acquisitionIntent, journal, indexedRequestId, recordHeld, now}: Ports) {
  function continuedOccurrence(captured: SourceCapture, continuation: Continuation) {
    const inventory = captureInventory(captured);
    if (!pluralCapture(captured)) return inventory[0];
    const identity = continuation.acquisition_occurrence;
    const occurrence = identity === undefined ? undefined : inventory.find(
      item => canonicalJson(occurrenceIdentity(item)) === canonicalJson(identity));
    if (occurrence === undefined) fail('HeldAcquisitionChanged');
    return occurrence;
  }

  function admittedRead(captured: Pick<CapturedRequest, 'principalId'>, occurrence: CapturedOccurrence, {checkpointCid,
    earlier = [], prepareAttemptId}: ReadApprovalOptions = {}) {
    return Object.freeze({checkpointCid,
      readTuple: occurrence.readTuple, acquisition: occurrence,
      principalId: captured.principalId, earlier: [...earlier],
      prepareAttemptId});
  }

  // The exact held evidence of one prepare attempt, from its ledger: the
  // continuation record, the captured submission and the request, checked
  // against each other.
  async function continuationOf(prepareAttemptId: string, continuationStateCid?: string) {
    const opened = await evidence.open(prepareAttemptId);
    // Every continuation of one attempt (a Run-acceptance hold and a
    // later read hold) binds the same captured submission; any held one
    // anchors it when no exact one is named.
    const [anchor] = continuationStateCid === undefined
      ? opened.held('continuation_record') : [continuationStateCid];
    if (anchor === undefined) fail('ContinuationEvidenceNotHeld');
    const continuation = await opened.record('continuation_record', anchor) as Continuation;
    const references = new Map(continuation.evidence.map(item =>
      [item.name, item.semantic_cid]));
    const captured = await opened.record('captured_input',
      references.get('captured_input')!) as CapturedRequest;
    const request = await opened.record('invocation_request',
      references.get('invocation_request')!) as InvocationRequest;
    const invocation = await opened.record('prepared_invocation',
      references.get('prepared_invocation')!) as Invocation;
    if ((continuation.boundary === 'acquisition' ? capturedValueCid(invocation)
      : contentCid(invocation)) !== continuation.invocation_cid ||
        invocation.captured_submission_cid !== capturedValueCid(captured) ||
        invocation.request_cid !== opened.requestCid ||
        contentCid(request) !== opened.requestCid ||
        continuation.prepare_attempt_id !== prepareAttemptId) {
      fail('ArtifactIntegrityFailed');
    }
    captureInventory(captured);
    if (continuation.boundary === 'acquisition') {
      const occurrence = continuedOccurrence(captured, continuation);
      if (occurrence === undefined || capturedValueCid(acquisitionIntent(
        opened.requestCid, captured, occurrence)) !== capturedValueCid(invocation)) {
        fail('HeldAcquisitionChanged');
      }
    }
    return {continuation, captured, request};
  }

  // A later read Checkpoint retains the whole earlier approval chain in the
  // same continuation evidence. Reconstruct occurrence grants from exact
  // held records, never from a sourceRef cache or from the last answer alone.
  async function earlierReadApprovals(prepareAttemptId: string, captured: CapturedRequest, earlier: readonly string[]) {
    const approved = new Map<string, ReturnType<typeof admittedRead>>();
    for (const checkpointCid of earlier) {
      const view = journal.inspect(checkpointCid);
      if (view?.prepareAttemptId !== prepareAttemptId) {
        fail('HeldAcquisitionChanged');
      }
      if (view.kind !== 'read_access') continue;
      const prior = await continuationOf(prepareAttemptId,
        view.continuationStateCid);
      if (capturedValueCid(prior.captured) !== capturedValueCid(captured)) {
        fail('HeldAcquisitionChanged');
      }
      const occurrence = continuedOccurrence(captured, prior.continuation)!;
      const key = occurrenceKey(occurrence);
      if (approved.has(key)) fail('HeldAcquisitionChanged');
      approved.set(key, admittedRead(captured, occurrence, {checkpointCid,
        earlier, prepareAttemptId}));
    }
    return approved;
  }
  async function heldRequestId(prepareAttemptId: string) {
    const indexed = await indexedRequestId(prepareAttemptId);
    if (indexed !== undefined) return indexed;
    const {captured} = await continuationOf(prepareAttemptId);
    await recordHeld(prepareAttemptId, captured.requestId);
    return captured.requestId;
  }

  const heldCheckpoint = (checkpointCid: string | null) => {
    const view = checkpointCid === null ? undefined
      : journal.inspect(checkpointCid);
    return view === undefined ? undefined : Object.freeze({
      checkpointId: view.checkpointId, checkpointCid: view.checkpointCid,
      kind: view.kind, expiresAt: view.expiresAt});
  };

  // The held projection of one prepare attempt, or undefined when the
  // attempt has created its Run (then the request journal answers) or does
  // not exist.
  function held(prepareAttemptId: string, requestId: string) {
    journal.expire();
    const preparation = journal.getPreparation(prepareAttemptId);
    if (preparation === undefined || preparation.status === 'run_created') {
      return undefined;
    }
    const checkpoint = heldCheckpoint(preparation.checkpointCid);
    const lookupExpiresAt = new Date((checkpoint === undefined ? now()
      : Date.parse(journal.inspect(checkpoint.checkpointCid)!.createdAt)) +
      LOOKUP_RETENTION_MS).toISOString();
    const base = {kind: 'held', requestId, prepareAttemptId,
      durability: 'durable', lookupExpiresAt} as const;
    if (preparation.status === 'waiting_checkpoint') {
      return Object.freeze({...base, state: 'waiting_checkpoint',
        checkpoint});
    }
    if (preparation.status === 'resuming') {
      return Object.freeze({...base, state: 'resuming',
        ...(checkpoint === undefined ? {} : {checkpoint})});
    }
    return Object.freeze({...base, state: 'ended',
      endReason: preparation.endReason ?? 'ended',
      ...(preparation.terminalErrorCode === null ? {} :
        {terminalErrorCode: preparation.terminalErrorCode})});
  }

  return {continuedOccurrence, admittedRead, continuationOf, earlierReadApprovals, heldRequestId, held};
}
