import {fail} from './effect-ledger-frames.mjs';

import type {effectApplicationControl} from '../host-common/effect-application-control.mjs';
import type {EffectDispatchClaim} from './effect-physical-dispatch.mjs';
import type {openSqliteEffectLedger} from './sqlite-effect-ledger.mjs';

type Control = ReturnType<typeof effectApplicationControl>;
type PhysicalLedger = ReturnType<typeof openSqliteEffectLedger>;
type StoredEntry = ReturnType<PhysicalLedger['current']>;
type BatchResponse = NonNullable<Parameters<PhysicalLedger['outcomeForLocator']>[1]>;
type SingleResponse = Exclude<NonNullable<ReturnType<PhysicalLedger['response']>>, BatchResponse>;
type Claim = EffectDispatchClaim;
type BatchEvidence = Readonly<{
  claims: readonly Claim[];
  stored: BatchResponse;
  typed: unknown;
  requestCid: string;
  locatorCids: readonly string[];
}>;
type RowOwner = Readonly<{
  claim?: Claim;
  claims?: readonly Claim[];
  batchRowIndex?: number;
}>;
type StoredOutcome = RowOwner & Readonly<{
  preview: unknown;
  memberIndex: number;
  previewRowIndex: number;
  responseEvidence?: BatchEvidence;
}>;
type MemberPartition = Readonly<{preview: unknown; memberIndex: number; rowOwners: readonly RowOwner[]}>;
type EvidenceReader = Readonly<{
  readClaimedResponse(claim: Claim | undefined): SingleResponse | undefined;
  readClaimedBatchResponse(claims: readonly Claim[]): BatchResponse | undefined;
  prepareOwnedBatchResponseEvidence(claims: readonly Claim[]): BatchEvidence;
}>;
type EvidenceOptions = Readonly<{
  control: Control;
  physical: PhysicalLedger;
  scopeCid: string;
  ownedBatchEvidence: WeakSet<BatchEvidence>;
  activePhysicalFlights: ReadonlyMap<string, symbol>;
  flightKey(entry: unknown): string;
  maxEntries: number;
  maxEntryBytes: number;
  maxResponseBytes: number;
  maxNodes: number;
  maxDepth: number;
  maxOutcomeNodes: number;
  maxOutcomeDepth: number;
  getLedger(): EvidenceReader;
}>;

export function prepareEffectLedgerEvidence({
  control, physical, scopeCid, ownedBatchEvidence, activePhysicalFlights, flightKey,
  maxEntries, maxEntryBytes, maxResponseBytes, maxNodes, maxDepth, maxOutcomeNodes, maxOutcomeDepth,
  getLedger,
}: EvidenceOptions) {
  const assertOwnedBatchEvidence = (claims: readonly Claim[] | undefined, evidence: BatchEvidence) => {
    if (!Array.isArray(claims) || !ownedBatchEvidence.has(evidence) ||
        claims !== evidence.claims ||
        claims.length !== evidence.locatorCids.length ||
        claims.some((item, index) =>
          control.logicalItemLocatorCid(item.locator) !==
            evidence.locatorCids[index] ||
          item.canonicalRequestCid !== evidence.requestCid)) {
      fail('EffectPhysicalResponseNotOwned');
    }
  };
  const admit = (wire: string) => control.admitLedgerEntry(
    wire, maxEntryBytes, maxNodes, maxDepth,
  );
  const validateStored = (row: StoredEntry) => {
    if (row === undefined) return undefined;
    if (row.logicalRequestScopeCid !== scopeCid) {
      fail('EffectLedgerScopeMismatch');
    }
    const entry = admit(row.entryJson);
    if (control.ledgerEntryCid(entry) !== row.entryCid ||
        control.ledgerEntryLocatorCid(entry) !== row.logicalItemLocatorCid ||
        control.ledgerEntryScopeCid(entry) !== row.logicalRequestScopeCid ||
        control.ledgerEntryWire(entry) !== row.entryJson) {
      fail('EffectLedgerIntegrityFailed');
    }
    return Object.freeze({row, entry});
  };
  const append = (entryJson: string) => {
    const next = admit(entryJson);
    if (control.ledgerEntryScopeCid(next) !== scopeCid) {
      fail('EffectLedgerScopeMismatch');
    }
    const locatorCid = control.ledgerEntryLocatorCid(next);
    const existing = validateStored(physical.current(locatorCid));
    if (existing?.row.entryCid === control.ledgerEntryCid(next)) {
      if (existing!.row.entryJson !== entryJson) {
        fail('EffectLedgerEntryCollision');
      }
      return Object.freeze({entry: existing!.row, created: false});
    }
    if (!control.ledgerEntryFollows(existing?.entry, next)) {
      fail('EffectLedgerInvalidTransition');
    }
    const result = physical.append({
      logicalRequestScopeCid: scopeCid,
      logicalItemLocatorCid: locatorCid,
      expectedRevision: existing?.row.revision ?? 0,
      entryCid: control.ledgerEntryCid(next),
      entryJson,
    });
    return Object.freeze({
      ...result,
      entry: validateStored(result.entry)!.row,
    });
  };
  const admitStoredRowOutcome = ({claim, claims, batchRowIndex, preview,
    memberIndex, previewRowIndex, responseEvidence}: StoredOutcome) => {
    if (responseEvidence !== undefined) {
      assertOwnedBatchEvidence(claims, responseEvidence);
    }
    const stored = responseEvidence === undefined
      ? claims === undefined
        ? getLedger().readClaimedResponse(claim)
        : getLedger().readClaimedBatchResponse(claims)
      : responseEvidence.stored;
    if (stored === undefined ||
        (claims === undefined && batchRowIndex !== undefined) ||
        (claims !== undefined &&
          (!Number.isSafeInteger(batchRowIndex) || batchRowIndex! < 0 ||
            batchRowIndex! >= claims.length))) {
      fail('EffectPhysicalResponseNotOwned');
    }
    const ownedClaim = (claims === undefined ? claim : claims[batchRowIndex!])!;
    const locatorCid = control.logicalItemLocatorCid(ownedClaim.locator);
    const current = validateStored(physical.current(locatorCid));
    const outcome = physical.outcomeForLocator(
      locatorCid, responseEvidence?.stored, claims === undefined && responseEvidence === undefined);
    if (current === undefined || outcome === undefined ||
        outcome.responsePhysicalSha256 !== stored.responsePhysicalSha256) {
      fail('EffectPhysicalOutcomeNotOwned');
    }
    const dispatchEntryCid = claims === undefined
      ? stored.dispatchEntryCid
      : stored.batchMembers![batchRowIndex!].dispatchEntryCid;
    const receipt = responseEvidence === undefined
      ? control.admitRowOutcomeReceipt(
        preview, memberIndex, previewRowIndex, dispatchEntryCid,
        stored.credentialUseCid, stored.responseBytes, stored.statusCode,
        outcome.outcomeJson, maxResponseBytes, maxEntryBytes,
        maxOutcomeNodes, maxOutcomeDepth)
      : control.admitRowOutcomeReceiptFromResponse(
        preview, memberIndex, previewRowIndex, dispatchEntryCid,
        responseEvidence.typed, outcome.outcomeJson, maxEntryBytes,
        maxOutcomeNodes, maxOutcomeDepth);
    if (receipt.identity !== outcome.outcomeCid) {
      fail('EffectPhysicalOutcomeCollision');
    }
    const history = physical.history(locatorCid, maxEntries).map(row =>
      validateStored(row)!.entry);
    const terminal = responseEvidence === undefined
      ? control.issueRowReceiptTerminalEntry(
        preview, memberIndex, previewRowIndex, ownedClaim.scope,
        ownedClaim.locator, ownedClaim.key, ownedClaim.canonicalRequestCid!,
        current.entry, history, dispatchEntryCid, stored.credentialUseCid,
        stored.responseBytes, stored.statusCode, receipt.wire,
        maxResponseBytes, maxEntryBytes,
        maxOutcomeNodes, maxOutcomeDepth)
      : control.issueRowReceiptTerminalEntryFromResponse(
        preview, memberIndex, previewRowIndex, ownedClaim.scope,
        ownedClaim.locator, ownedClaim.key, ownedClaim.canonicalRequestCid!,
        current.entry, history, dispatchEntryCid, responseEvidence.typed,
        receipt.wire, maxEntryBytes, maxOutcomeNodes, maxOutcomeDepth);
    return Object.freeze({current, receipt, terminal});
  };
  const memberReceiptEvidence = ({preview, memberIndex, rowOwners}: MemberPartition) => {
    if (!preview || !Number.isSafeInteger(memberIndex) ||
        !Array.isArray(rowOwners) || rowOwners.length > maxEntries) {
      fail('InvalidEffectMemberReceiptEvidence');
    }
    const claims = rowOwners.map((owner: RowOwner) => {
      const claim = owner?.claims === undefined ? owner?.claim
        : owner.claims?.[owner.batchRowIndex!];
      if (!claim?.basis || !claim.scope || !claim.locator || !claim.key ||
          typeof claim.canonicalRequestCid !== 'string' ||
          typeof claim.intentFingerprintCid !== 'string' ||
          owner?.claims !== undefined &&
            (!Array.isArray(owner.claims) ||
              !Number.isSafeInteger(owner.batchRowIndex) ||
              owner.batchRowIndex! < 0 ||
              owner.batchRowIndex! >= owner.claims.length)) {
        fail('InvalidEffectMemberReceiptEvidence');
      }
      return claim;
    });
    const locatorCids = claims.map(claim =>
      control.logicalItemLocatorCid(claim.locator));
    const heads = physical.currentSnapshot(locatorCids).map(row =>
      validateStored(row)?.entry);
    const activeOwners = heads.map(head => head !== undefined &&
      activePhysicalFlights.has(flightKey(head)));
    const batchEvidence = new Map<readonly Claim[], BatchEvidence>();
    const terminalWires = heads.map((head, rowIndex) => {
      if (head === undefined ||
          ![2, 3, 4].includes(control.ledgerEntryStateCode(head))) {
        return undefined;
      }
      const owner = rowOwners[rowIndex];
      let responseEvidence;
      if (owner.claims !== undefined) {
        responseEvidence = batchEvidence.get(owner.claims);
        if (responseEvidence === undefined) {
          responseEvidence = getLedger().prepareOwnedBatchResponseEvidence(
            owner.claims);
          batchEvidence.set(owner.claims, responseEvidence);
        }
      }
      const {current, receipt, terminal} = admitStoredRowOutcome({
        ...(owner.claims === undefined ? {claim: claims[rowIndex]} : {
          claims: owner.claims, batchRowIndex: owner.batchRowIndex,
        }),
        preview, memberIndex, previewRowIndex: rowIndex,
        responseEvidence,
      });
      if (control.ledgerEntryCid(current.entry) !==
          control.ledgerEntryCid(head) ||
          control.ledgerEntryCid(terminal) !==
            control.ledgerEntryCid(head)) {
        fail('EffectMemberReceiptHeadChanged');
      }
      return receipt.wire;
    });
    return [preview, memberIndex, claims.map(claim => claim.scope),
      claims.map(claim => claim.locator),
      claims.map(claim => claim.key),
      claims.map(claim => claim.basis), heads, activeOwners,
      terminalWires] as const;
  };
  return {assertOwnedBatchEvidence, validateStored, append, admitStoredRowOutcome, memberReceiptEvidence};
}
