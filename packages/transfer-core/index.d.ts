declare const ownerHandle: unique symbol;

export type TransferRequest = {readonly [ownerHandle]: 'transfer-request'};
export type TransferRecord = {readonly [ownerHandle]: 'transfer-record'};
export type DurableTransferRecord = {
  readonly [ownerHandle]: 'durable-transfer-record'
};
export type TransferTransition = {readonly [ownerHandle]: 'transfer-transition'};
export type TransferLimits = Readonly<{
  maxChunks: number;
  maxManifestBytes: number;
  maxReferencedBytes: number | bigint;
}>;
export type TransferProjection = Readonly<{
  cid: string;
  route: string;
  sourceSiteKey: string;
  sourceSiteGeneration: string;
  destinationSiteKey: string;
  destinationSiteGeneration: string;
  materialGeneration: string;
  manifestCid: string;
  maxBytes: string;
  expiresUnixMs: string;
  sourceGrantCid: string;
  destinationGrantCid: string;
  routeCapabilityCid: string;
}>;

export function admitEnvelopeJson(body: string, claimedRequestCid: string,
  claimedManifestCid: string, bounds: TransferLimits): TransferRequest;
export function requestCid(request: TransferRequest): string;
export function requestJournalKey(request: TransferRequest):
  ReadonlyArray<string>;
export function requestProjection(request: TransferRequest): TransferProjection;
export function chunks(request: TransferRequest):
  ReadonlyArray<Readonly<{cid: string; byteLength: bigint}>>;
export function activeAt(request: TransferRequest,
  trustedNow: number | bigint): boolean;
export function openRecord(request: TransferRequest): TransferRecord;
export function recordDurableJson(record: TransferRecord): string;
export function admitDurableJson(body: string,
  bounds: TransferLimits): DurableTransferRecord;
export function restoreDurable(durable: DurableTransferRecord): TransferRecord;
export function durableRevision(durable: DurableTransferRecord): number;
export function durableRequestCid(durable: DurableTransferRecord): string;
export function prepareStart(record: TransferRecord): TransferTransition;
export function prepareSourceSettled(record: TransferRecord,
  integrityVerified: boolean, objectSealed: boolean): TransferTransition;
export function prepareDestinationCommit(record: TransferRecord):
  TransferTransition;
export function prepareUnknown(record: TransferRecord): TransferTransition;
export function prepareFailure(record: TransferRecord, cancelled: boolean,
  sourceAccessStopped: boolean): TransferTransition;
export function prepareCleanup(record: TransferRecord,
  sourceAccessStopped: boolean, destinationTemporaryReclaimed: boolean,
  objectUseReleased: boolean): TransferTransition;
export function transitionDurableJson(transition: TransferTransition): string;
export function transitionExpectedRevision(transition: TransferTransition): number;
/** Call only after the exact next durable body was atomically persisted. */
export function commitTransition(transition: TransferTransition): TransferRecord;
export function replyJson(record: TransferRecord): string;
export function recordIsDestinationCommitted(record: TransferRecord): boolean;
export function recordRevision(record: TransferRecord): number;
export function recordRequest(record: TransferRecord): TransferRequest;
/** Start=0, copying=1, source-settled=2, committed=3, reconcile=4. */
export function directProgress(record: TransferRecord): number;
