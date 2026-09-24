import * as owner from './dist/remote_transfer_abi.js';

function checked(result) {
  if (result?.$tag === 1) return result._0;
  if (result?.$tag === 0) {
    throw Object.assign(new Error('TransferOwnerRejected', {cause: result._0}),
      {code: 'TransferOwnerRejected'});
  }
  throw Object.assign(new Error('InvalidTransferOwnerResult'),
    {code: 'InvalidTransferOwnerResult'});
}

const limits = value => {
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

export const admitEnvelopeJson = (body, claimedRequestCid,
  claimedManifestCid, bounds) => {
  if (typeof body !== 'string' ||
      typeof claimedRequestCid !== 'string' ||
      typeof claimedManifestCid !== 'string') {
    throw new TypeError('InvalidTransferEnvelopeInput');
  }
  return checked(owner.transferAdmitEnvelopeJson(body, claimedRequestCid,
    claimedManifestCid, ...limits(bounds)));
};
export const requestCid = owner.transferRequestCid;
export const requestJournalKey = request => {
  const key = owner.transferRequestJournalKey(request);
  if (!Array.isArray(key) || key.length !== 4 ||
      !key.every(value => typeof value === 'string')) {
    throw new Error('InvalidTransferJournalKey');
  }
  return Object.freeze([...key]);
};
export const requestProjection = request => {
  const fields = owner.transferRequestProjection(request);
  if (!Array.isArray(fields) || fields.length !== 13 ||
      !fields.every(value => typeof value === 'string')) {
    throw new Error('InvalidTransferProjection');
  }
  const [cid, route, sourceSiteKey, sourceSiteGeneration,
    destinationSiteKey, destinationSiteGeneration, materialGeneration,
    manifestCid, maxBytes, expiresUnixMs, sourceGrantCid,
    destinationGrantCid, routeCapabilityCid] = fields;
  return Object.freeze({cid, route, sourceSiteKey, sourceSiteGeneration,
    destinationSiteKey, destinationSiteGeneration, materialGeneration,
    manifestCid, maxBytes, expiresUnixMs, sourceGrantCid,
    destinationGrantCid, routeCapabilityCid});
};
export const chunks = request => {
  const cids = owner.transferChunkCids(request);
  const lengths = owner.transferChunkByteLengths(request);
  if (!Array.isArray(cids) || !Array.isArray(lengths) ||
      cids.length !== lengths.length ||
      !cids.every(cid => typeof cid === 'string') ||
      !lengths.every(length => typeof length === 'bigint' && length >= 0n)) {
    throw new Error('InvalidTransferChunks');
  }
  return Object.freeze(cids.map((cid, index) =>
    Object.freeze({cid, byteLength: lengths[index]})));
};
export const activeAt = (request, trustedNow) => {
  if (!(typeof trustedNow === 'bigint' && trustedNow >= 0n ||
      Number.isSafeInteger(trustedNow) && trustedNow >= 0)) {
    throw new TypeError('InvalidTransferClock');
  }
  return owner.transferActiveAt(request, BigInt(trustedNow));
};
export const openRecord = owner.transferOpenRecord;
export const recordDurableJson = record =>
  checked(owner.transferRecordDurableJson(record));
export const admitDurableJson = (body, bounds) => {
  if (typeof body !== 'string') throw new TypeError('InvalidTransferDurableInput');
  return checked(owner.transferAdmitDurableJson(body, ...limits(bounds)));
};
export const restoreDurable = durable =>
  checked(owner.transferRestoreDurable(durable));
export const durableRevision = owner.transferDurableRevision;
export const durableRequestCid = owner.transferDurableRequestCid;
export const prepareStart = record => checked(owner.transferPrepareStart(record));
export const prepareSourceSettled = (record, integrityVerified,
  objectSealed) => checked(owner.transferPrepareSourceSettled(record,
    integrityVerified, objectSealed));
export const prepareDestinationCommit = record =>
  checked(owner.transferPrepareDestinationCommit(record));
export const prepareUnknown = record =>
  checked(owner.transferPrepareUnknown(record));
export const prepareFailure = (record, cancelled, sourceAccessStopped) =>
  checked(owner.transferPrepareFailure(record, cancelled,
    sourceAccessStopped));
export const prepareCleanup = (record, sourceAccessStopped,
  destinationTemporaryReclaimed, objectUseReleased) =>
  checked(owner.transferPrepareCleanup(record, sourceAccessStopped,
    destinationTemporaryReclaimed, objectUseReleased));
export const transitionDurableJson = transition =>
  checked(owner.transferTransitionDurableJson(transition));
export const transitionExpectedRevision =
  owner.transferTransitionExpectedRevision;
/** Call only after the exact next durable body was atomically persisted. */
export const commitTransition = transition =>
  checked(owner.transferCommitTransition(transition));
export const replyJson = record => checked(owner.transferReplyJson(record));
export const recordIsDestinationCommitted =
  owner.transferRecordIsDestinationCommitted;
export const recordRevision = owner.transferRecordRevision;
export const recordRequest = owner.transferRecordRequest;
export const directProgress = owner.transferDirectProgress;
