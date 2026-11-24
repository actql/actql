// The package builder installs this MoonBit ABI after TypeScript emit.
// Result values remain opaque until the JavaScript facade checks their tag.
declare module '*/dist/remote_transfer_abi.js' {
  type Public = typeof import('./index.d.ts');
  type Request = import('./index.d.ts').TransferRequest;
  type Record = import('./index.d.ts').TransferRecord;
  type Durable = import('./index.d.ts').DurableTransferRecord;
  type Transition = import('./index.d.ts').TransferTransition;
  type Result = unknown;

  export function transferAdmitEnvelopeJson(body: string, requestCid: string, manifestCid: string,
    maxChunks: number, maxManifestBytes: number, maxReferencedBytes: bigint): Result;
  export const transferRequestCid: Public['requestCid'];
  export function transferRequestJournalKey(request: Request): unknown;
  export function transferRequestProjection(request: Request): unknown;
  export function transferChunkCids(request: Request): unknown;
  export function transferChunkByteLengths(request: Request): unknown;
  export function transferActiveAt(request: Request, trustedNow: bigint): boolean;
  export const transferOpenRecord: Public['openRecord'];
  export function transferRecordDurableJson(record: Record): Result;
  export function transferAdmitDurableJson(body: string, maxChunks: number,
    maxManifestBytes: number, maxReferencedBytes: bigint): Result;
  export function transferRestoreDurable(durable: Durable): Result;
  export const transferDurableRevision: Public['durableRevision'];
  export const transferDurableRequestCid: Public['durableRequestCid'];
  export function transferPrepareStart(record: Record): Result;
  export function transferPrepareSourceSettled(record: Record, integrityVerified: boolean, objectSealed: boolean): Result;
  export function transferPrepareDestinationCommit(record: Record): Result;
  export function transferPrepareUnknown(record: Record): Result;
  export function transferPrepareFailure(record: Record, cancelled: boolean, sourceAccessStopped: boolean): Result;
  export function transferPrepareCleanup(record: Record, sourceAccessStopped: boolean,
    destinationTemporaryReclaimed: boolean, objectUseReleased: boolean): Result;
  export function transferTransitionDurableJson(transition: Transition): Result;
  export const transferTransitionExpectedRevision: Public['transitionExpectedRevision'];
  export function transferCommitTransition(transition: Transition): Result;
  export function transferReplyJson(record: Record): Result;
  export const transferRecordIsDestinationCommitted: Public['recordIsDestinationCommitted'];
  export const transferRecordRevision: Public['recordRevision'];
  export const transferRecordRequest: Public['recordRequest'];
  export const transferDirectProgress: Public['directProgress'];
}
