import {runtimeField, runtimeIsError, runtimeIsOk} from './compiler-binding.generated.mjs';
import * as owner from './dist/remote_transfer_abi.js';
import type {DurableTransferRecord, TransferLimits, TransferProjection, TransferRecord,
  TransferRequest, TransferTransition} from './index.js';

function checked<Value>(result: unknown): Value {
  if (runtimeIsOk(result)) return runtimeField(result, 0) as Value;
  if (runtimeIsError(result)) {
    throw Object.assign(new Error('TransferOwnerRejected', {cause: runtimeField(result, 0)}),
      {code: 'TransferOwnerRejected'});
  }
  throw Object.assign(new Error('InvalidTransferOwnerResult'),
    {code: 'InvalidTransferOwnerResult'});
}

const limits = (value: TransferLimits): [number, number, bigint] => {
  if (value === null || typeof value !== 'object' ||
      !Number.isSafeInteger(value.maxChunks) || value.maxChunks < 1 ||
      !Number.isSafeInteger(value.maxManifestBytes) ||
      value.maxManifestBytes < 1 ||
      !(typeof value.maxReferencedBytes === 'bigint' &&
        value.maxReferencedBytes > 0n &&
        value.maxReferencedBytes <= 9223372036854775807n ||
        Number.isSafeInteger(value.maxReferencedBytes) &&
        value.maxReferencedBytes > 0)) {
    throw new TypeError('InvalidTransferLimits');
  }
  return [value.maxChunks, value.maxManifestBytes,
    BigInt(value.maxReferencedBytes)];
};

export const admitEnvelopeJson = (body: string, claimedRequestCid: string,
  claimedManifestCid: string, bounds: TransferLimits) => {
  if (typeof body !== 'string' ||
      typeof claimedRequestCid !== 'string' ||
      typeof claimedManifestCid !== 'string') {
    throw new TypeError('InvalidTransferEnvelopeInput');
  }
  return checked<TransferRequest>(owner.transferAdmitEnvelopeJson(body, claimedRequestCid,
    claimedManifestCid, ...limits(bounds)));
};
export const requestCid = owner.transferRequestCid;
export const requestJournalKey = (request: TransferRequest): readonly string[] => {
  const key = owner.transferRequestJournalKey(request);
  if (!Array.isArray(key) || key.length !== 4 ||
      !key.every(value => typeof value === 'string')) {
    throw new Error('InvalidTransferJournalKey');
  }
  return Object.freeze([...key]) as readonly string[];
};
export const requestProjection = (request: TransferRequest): TransferProjection => {
  const fields = owner.transferRequestProjection(request);
  if (!Array.isArray(fields) || fields.length !== 13 ||
      !fields.every(value => typeof value === 'string')) {
    throw new Error('InvalidTransferProjection');
  }
  const [cid, route, sourceSiteKey, sourceSiteGeneration,
    destinationSiteKey, destinationSiteGeneration, materialGeneration,
    manifestCid, maxBytes, expiresUnixMs, sourceGrantCid,
    destinationGrantCid, routeCapabilityCid] = fields as string[];
  return Object.freeze({cid, route, sourceSiteKey, sourceSiteGeneration,
    destinationSiteKey, destinationSiteGeneration, materialGeneration,
    manifestCid, maxBytes, expiresUnixMs, sourceGrantCid,
    destinationGrantCid, routeCapabilityCid});
};
export const chunks = (request: TransferRequest): readonly Readonly<{cid: string; byteLength: bigint}>[] => {
  const cids = owner.transferChunkCids(request);
  const lengths = owner.transferChunkByteLengths(request);
  if (!Array.isArray(cids) || !Array.isArray(lengths) ||
      cids.length !== lengths.length ||
      !cids.every(cid => typeof cid === 'string') ||
      !lengths.every(length => typeof length === 'bigint' && length >= 0n)) {
    throw new Error('InvalidTransferChunks');
  }
  return Object.freeze((cids as string[]).map((cid, index) =>
    Object.freeze({cid, byteLength: (lengths as bigint[])[index]})));
};
export const activeAt = (request: TransferRequest, trustedNow: number | bigint) => {
  if (!(typeof trustedNow === 'bigint' && trustedNow >= 0n ||
      Number.isSafeInteger(trustedNow) && trustedNow >= 0)) {
    throw new TypeError('InvalidTransferClock');
  }
  return owner.transferActiveAt(request, BigInt(trustedNow));
};
export const openRecord = owner.transferOpenRecord;
export const recordDurableJson = (record: TransferRecord) =>
  checked<string>(owner.transferRecordDurableJson(record));
export const admitDurableJson = (body: string, bounds: TransferLimits) => {
  if (typeof body !== 'string') throw new TypeError('InvalidTransferDurableInput');
  return checked<DurableTransferRecord>(owner.transferAdmitDurableJson(body, ...limits(bounds)));
};
export const restoreDurable = (durable: DurableTransferRecord) =>
  checked<TransferRecord>(owner.transferRestoreDurable(durable));
export const durableRevision = owner.transferDurableRevision;
export const durableRequestCid = owner.transferDurableRequestCid;
export const prepareStart = (record: TransferRecord) => checked<TransferTransition>(owner.transferPrepareStart(record));
export const prepareSourceSettled = (record: TransferRecord, integrityVerified: boolean,
  objectSealed: boolean) => checked<TransferTransition>(owner.transferPrepareSourceSettled(record,
    integrityVerified, objectSealed));
export const prepareDestinationCommit = (record: TransferRecord) =>
  checked<TransferTransition>(owner.transferPrepareDestinationCommit(record));
export const prepareUnknown = (record: TransferRecord) =>
  checked<TransferTransition>(owner.transferPrepareUnknown(record));
export const prepareFailure = (record: TransferRecord, cancelled: boolean, sourceAccessStopped: boolean) =>
  checked<TransferTransition>(owner.transferPrepareFailure(record, cancelled,
    sourceAccessStopped));
export const prepareCleanup = (record: TransferRecord, sourceAccessStopped: boolean,
  destinationTemporaryReclaimed: boolean, objectUseReleased: boolean) =>
  checked<TransferTransition>(owner.transferPrepareCleanup(record, sourceAccessStopped,
    destinationTemporaryReclaimed, objectUseReleased));
export const transitionDurableJson = (transition: TransferTransition) =>
  checked<string>(owner.transferTransitionDurableJson(transition));
export const transitionExpectedRevision =
  owner.transferTransitionExpectedRevision;
/** Call only after the exact next durable body was atomically persisted. */
export const commitTransition = (transition: TransferTransition) =>
  checked<TransferRecord>(owner.transferCommitTransition(transition));
export const replyJson = (record: TransferRecord) => checked<string>(owner.transferReplyJson(record));
export const recordIsDestinationCommitted =
  owner.transferRecordIsDestinationCommitted;
export const recordRevision = owner.transferRecordRevision;
export const recordRequest = owner.transferRecordRequest;
export const directProgress = owner.transferDirectProgress;
