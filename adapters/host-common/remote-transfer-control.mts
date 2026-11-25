import {checked} from './runtime-result.mjs';
import type {SynchronousRuntimeData} from './runtime-result.mjs';
import {tuplePair} from './runtime-tuple.mjs';
import type {TransferLimits} from '../../packages/transfer-core/index.js';

type Quantity = number | bigint;
type DestinationReceipt = Extract<SynchronousRuntimeData, object>;
type PhysicalChunk = Readonly<{cid: string; byteLength: Quantity; rowCount: number}>;
type PhysicalManifest = Readonly<{
  version: string;
  schemaContractCid: string;
  viewContractCid: string;
  codecContractCid: string;
  rowCount: number;
  chunks: readonly PhysicalChunk[];
}>;
type TransferDeclaration = Readonly<{
  coordinatorAuthority: string;
  transferAttemptId: string;
  route: string;
  sourceSite: string;
  sourceSiteGeneration: number;
  destinationSite: string;
  destinationSiteGeneration: number;
  sourceMaterialGeneration: string;
  physicalManifest: PhysicalManifest;
  limits: TransferLimits;
  capacityBytes: Quantity;
  expiresAtMilliseconds: Quantity;
  sourceGrantCid: string;
  destinationGrantCid: string;
  routeCapabilityCid: string;
}>;

// The generated Common bridge still owns all opaque handles and Result admission.
type CommonTransferBindings = {
  strategyRemoteTransferPrepare(
    coordinatorAuthority: string, transferAttemptId: string, route: number, sourceSite: string,
    sourceSiteGeneration: number, destinationSite: string, destinationSiteGeneration: number,
    sourceMaterialGeneration: string, manifestVersion: string, schemaContractCid: string,
    viewContractCid: string, codecContractCid: string, rowCount: number, chunkCids: readonly string[],
    chunkByteLengths: readonly bigint[], chunkRowCounts: readonly number[], maxChunks: number,
    maxManifestBytes: number, maxReferencedBytes: bigint, capacityBytes: bigint, expiresAtMs: bigint,
    sourceGrantCid: string, destinationGrantCid: string, routeCapabilityCid: string,
  ): unknown;
  strategyRemoteTransferIdentity(request: unknown): string;
  strategyRemoteTransferJson(request: unknown): unknown;
  strategyRemoteTransferManifestJson(request: unknown): unknown;
  strategyRemoteTransferAdmitJson(
    body: string, manifestBody: string, claimedRequestCid: string, claimedManifestCid: string,
    maxChunks: number, maxManifestBytes: number, maxReferencedBytes: bigint,
  ): unknown;
  strategyRemoteTransferAdmissionEnvelopeJson(request: unknown): unknown;
  strategyRemoteTransferAdmissionEnvelopeAdmitJson(
    body: string, claimedRequestCid: string, claimedManifestCid: string, maxChunks: number,
    maxManifestBytes: number, maxReferencedBytes: bigint,
  ): unknown;
  strategyRemoteTransferReplyJson(record: unknown): unknown;
  strategyRemoteTransferReplyAdmitJson(body: string, request: unknown): unknown;
  strategyRemoteTransferStoreUploadReplyJson(
    request: unknown, kind: number, nextChunk: number, isSealed: boolean,
  ): unknown;
  strategyRemoteTransferStoreUploadReplyAdmitJson(body: string, request: unknown, kind: number): unknown;
  strategyRemoteTransferStoreUploadReplyProjection(reply: unknown): readonly string[];
  strategyRemoteTransferStoreUseReplyJson(
    request: unknown, useId: string, kind: number, isComplete: boolean,
  ): unknown;
  strategyRemoteTransferStoreUseReplyAdmitJson(
    body: string, request: unknown, useId: string, kind: number,
  ): unknown;
  strategyRemoteTransferStoreUseReplyProjection(reply: unknown): readonly string[];
  strategyRemoteTransferStoreUseCancellationReplyJson(request: unknown, useId: string): unknown;
  strategyRemoteTransferStoreUseCancellationReplyAdmitJson(
    body: string, request: unknown, useId: string,
  ): unknown;
  strategyRemoteTransferStoreUseCancellationReplyProjection(reply: unknown): readonly string[];
  strategyRemoteTransferDestinationReceiptPrepare(
    request: unknown, destinationMaterialGeneration: string,
  ): unknown;
  strategyRemoteTransferDestinationReceiptJson(receipt: unknown): unknown;
  strategyRemoteTransferDestinationReceiptIdentity(receipt: unknown): string;
  strategyRemoteTransferDestinationReceiptAdmitJson(
    body: string, request: unknown, claimedReceiptCid: string,
  ): unknown;
  strategyRemoteTransferDestinationReceiptProjection(receipt: unknown): readonly string[];
  strategyRemoteTransferStoreUsePrepare(request: unknown, useId: string): unknown;
  strategyRemoteTransferStoreUseIdentity(storeUse: unknown): string;
  strategyRemoteTransferStoreUseProjection(storeUse: unknown): readonly string[];
  strategyRemoteTransferStoreUseOpen(storeUse: unknown): unknown;
  strategyRemoteTransferStoreUseStartPrepare(record: unknown): unknown;
  strategyRemoteTransferStoreUseProgressPrepare(
    record: unknown, confirmedChunks: number, confirmedBytes: bigint,
  ): unknown;
  strategyRemoteTransferStoreUseCompletePrepare(record: unknown, receipt: unknown): unknown;
  strategyRemoteTransferStoreUseFailurePrepare(record: unknown, readerStopped: boolean): unknown;
  strategyRemoteTransferStoreUseUnknownPrepare(record: unknown): unknown;
  strategyRemoteTransferStoreUseCleanupPrepare(record: unknown): unknown;
  strategyRemoteTransferStoreUseTransitionProjection(
    transition: unknown,
  ): readonly [readonly string[], readonly string[]];
  strategyRemoteTransferStoreUseTransitionJournalKey(transition: unknown): readonly string[];
  strategyRemoteTransferStoreUseTransitionCommit(transition: unknown, durable: boolean): unknown;
  strategyRemoteTransferStoreUseRecordProjection(record: unknown): readonly string[];
  strategyRemoteTransferStoreUseRecordRestore(
    storeUse: unknown, revision: number, state: number, cleanup: number, confirmedChunks: number,
    confirmedBytes: bigint, readerStopped: boolean, destinationReceiptCid: string,
  ): unknown;
  strategyRemoteTransferProjection(request: unknown): readonly string[];
  strategyRemoteTransferJournalKey(request: unknown): readonly string[];
  strategyRemoteTransferChunkCids(request: unknown): readonly string[];
  strategyRemoteTransferChunkByteLengths(request: unknown): readonly bigint[];
  strategyRemoteTransferChunkRowCounts(request: unknown): readonly number[];
  strategyRemoteTransferActiveAt(request: unknown, trustedNowMs: bigint): boolean;
  strategyRemoteTransferOpen(request: unknown): unknown;
  strategyRemoteTransferStartPrepare(record: unknown): unknown;
  strategyRemoteTransferSourceSettledPrepare(
    record: unknown, integrityVerified: boolean, storeObjectSealed: boolean,
  ): unknown;
  strategyRemoteTransferDestinationCommitPrepare(record: unknown): unknown;
  strategyRemoteTransferFailurePrepare(
    record: unknown, cancelled: boolean, sourceAccessStopped: boolean,
  ): unknown;
  strategyRemoteTransferUnknownPrepare(record: unknown): unknown;
  strategyRemoteTransferCleanupPrepare(
    record: unknown, sourceAccessStopped: boolean, destinationTemporaryReclaimed: boolean,
    objectUseReleased: boolean,
  ): unknown;
  strategyRemoteTransferTransitionProjection(
    transition: unknown,
  ): readonly [readonly number[], readonly number[]];
  strategyRemoteTransferTransitionJournalKey(transition: unknown): readonly string[];
  strategyRemoteTransferTransitionCommit(transition: unknown, durable: boolean): unknown;
  strategyRemoteTransferRecordProjection(record: unknown): readonly number[];
  strategyRemoteTransferRecordRequestIdentity(record: unknown): string;
  strategyRemoteTransferRecordIsDestinationCommitted(record: unknown): boolean;
  strategyRemoteTransferDirectCleanupConfirmed(record: unknown): boolean;
  strategyRemoteTransferDirectProgress(record: unknown): number;
  strategyRemoteTransferDirectCancelDecision(record: unknown): number;
  strategyRemoteTransferRecordRevision(record: unknown): number;
  strategyRemoteTransferRecordRestore(request: unknown, state: readonly number[]): unknown;
};

const remoteTransferControls = new WeakMap<object, ReturnType<typeof createRemoteTransferControl>>();

export function remoteTransferControl(moon: CommonTransferBindings) {
  let control = remoteTransferControls.get(moon);
  if (control !== undefined) return control;
  control = createRemoteTransferControl(moon);
  remoteTransferControls.set(moon, control);
  return control;
}

function createRemoteTransferControl(moon: CommonTransferBindings) {
  const int64 = (value: Quantity, label: string) => {
    if (typeof value === 'bigint' && value >= 0n) return value;
    if (Number.isSafeInteger(value) && value >= 0) return BigInt(value);
    throw new TypeError(`Invalid Remote Transfer ${label}`);
  };
  const requestFields = (request: TransferDeclaration): Parameters<CommonTransferBindings['strategyRemoteTransferPrepare']> => {
    if (request === null || typeof request !== 'object' ||
        request.physicalManifest === null ||
        typeof request.physicalManifest !== 'object' ||
        !Array.isArray(request.physicalManifest.chunks) ||
        request.limits === null || typeof request.limits !== 'object' ||
        !Number.isSafeInteger(request.limits.maxChunks) ||
        request.limits.maxChunks < 0 ||
        !Number.isSafeInteger(request.limits.maxManifestBytes) ||
        request.limits.maxManifestBytes < 0 ||
        !Number.isSafeInteger(request.sourceSiteGeneration) ||
        request.sourceSiteGeneration < 0 ||
        !Number.isSafeInteger(request.destinationSiteGeneration) ||
        request.destinationSiteGeneration < 0 ||
        !Number.isSafeInteger(request.physicalManifest.rowCount) ||
        request.physicalManifest.rowCount < 0 ||
        request.physicalManifest.chunks.length > request.limits.maxChunks) {
      throw new TypeError('Invalid Remote Transfer request');
    }
    const physical = request.physicalManifest;
    const chunks: readonly PhysicalChunk[] = physical.chunks;
    if (chunks.some(chunk => chunk === null || typeof chunk !== 'object' ||
      !Number.isSafeInteger(chunk.rowCount) || chunk.rowCount < 0)) {
      throw new TypeError('Invalid Remote Transfer chunks');
    }
    return [
      request.coordinatorAuthority,
      request.transferAttemptId,
      request.route === 'direct' ? 0 : request.route === 'store' ? 1 : -1,
      request.sourceSite,
      request.sourceSiteGeneration,
      request.destinationSite,
      request.destinationSiteGeneration,
      request.sourceMaterialGeneration,
      physical.version,
      physical.schemaContractCid,
      physical.viewContractCid,
      physical.codecContractCid,
      physical.rowCount,
      chunks.map(chunk => chunk.cid),
      chunks.map(chunk => int64(chunk.byteLength, 'chunk length')),
      chunks.map(chunk => chunk.rowCount),
      request.limits.maxChunks,
      request.limits.maxManifestBytes,
      int64(request.limits.maxReferencedBytes, 'referenced-byte limit'),
      int64(request.capacityBytes, 'capacity'),
      int64(request.expiresAtMilliseconds, 'expiry'),
      request.sourceGrantCid,
      request.destinationGrantCid,
      request.routeCapabilityCid,
    ];
  };
  return Object.freeze({
    prepare: (request: TransferDeclaration) => checked(
      moon.strategyRemoteTransferPrepare(...requestFields(request)),
    ),
    identity: moon.strategyRemoteTransferIdentity,
    requestJson: (value: unknown) => checked(moon.strategyRemoteTransferJson(value)) as string,
    manifestJson: (value: unknown) => checked(
      moon.strategyRemoteTransferManifestJson(value),
    ) as string,
    admitJson: (body: string, manifestBody: string, claimedRequestCid: string, claimedManifestCid: string, limits: TransferLimits) => {
      if (limits === null || typeof limits !== 'object' ||
          !Number.isSafeInteger(limits.maxChunks) || limits.maxChunks < 0 ||
          !Number.isSafeInteger(limits.maxManifestBytes) ||
          limits.maxManifestBytes < 0) {
        throw new TypeError('Invalid Remote Transfer wire limits');
      }
      return checked(moon.strategyRemoteTransferAdmitJson(
        body,
        manifestBody,
        claimedRequestCid,
        claimedManifestCid,
        limits.maxChunks,
        limits.maxManifestBytes,
        int64(limits.maxReferencedBytes, 'referenced-byte limit'),
      ));
    },
    admissionEnvelopeJson: (value: unknown) => checked(
      moon.strategyRemoteTransferAdmissionEnvelopeJson(value),
    ) as string,
    admitAdmissionEnvelopeJson: (body: string, claimedRequestCid: string, claimedManifestCid: string, limits: TransferLimits) => {
      if (limits === null || typeof limits !== 'object' ||
          !Number.isSafeInteger(limits.maxChunks) || limits.maxChunks < 0 ||
          !Number.isSafeInteger(limits.maxManifestBytes) ||
          limits.maxManifestBytes < 0) {
        throw new TypeError('Invalid Remote Transfer wire limits');
      }
      return checked(moon.strategyRemoteTransferAdmissionEnvelopeAdmitJson(
        body,
        claimedRequestCid,
        claimedManifestCid,
        limits.maxChunks,
        limits.maxManifestBytes,
        int64(limits.maxReferencedBytes, 'referenced-byte limit'),
      ));
    },
    replyJson: (value: unknown) => checked(
      moon.strategyRemoteTransferReplyJson(value),
    ) as string,
    admitReplyJson: (body: string, request: unknown) => checked(
      moon.strategyRemoteTransferReplyAdmitJson(body, request),
    ),
    storeUploadReplyJson: (request: unknown, kind: string, nextChunk: number, sealed: boolean) => checked(
      moon.strategyRemoteTransferStoreUploadReplyJson(
        request,
        kind === 'admission' ? 0 : kind === 'chunk' ? 1 :
          kind === 'commit' ? 2 : -1,
        nextChunk,
        sealed,
      ),
    ) as string,
    admitStoreUploadReplyJson: (body: string, request: unknown, kind: string) => checked(
      moon.strategyRemoteTransferStoreUploadReplyAdmitJson(
        body,
        request,
        kind === 'admission' ? 0 : kind === 'chunk' ? 1 :
          kind === 'commit' ? 2 : -1,
      ),
    ),
    storeUploadReplyProjection:
      moon.strategyRemoteTransferStoreUploadReplyProjection,
    storeUseReplyJson: (request: unknown, useId: string, kind: string, complete: boolean) => checked(
      moon.strategyRemoteTransferStoreUseReplyJson(
        request,
        useId,
        kind === 'admission' ? 0 : kind === 'completion' ? 1 : -1,
        complete,
      ),
    ) as string,
    admitStoreUseReplyJson: (body: string, request: unknown, useId: string, kind: string) => checked(
      moon.strategyRemoteTransferStoreUseReplyAdmitJson(
        body,
        request,
        useId,
        kind === 'admission' ? 0 : kind === 'completion' ? 1 : -1,
      ),
    ),
    storeUseReplyProjection:
      moon.strategyRemoteTransferStoreUseReplyProjection,
    storeUseCancellationReplyJson: (request: unknown, useId: string) => checked(
      moon.strategyRemoteTransferStoreUseCancellationReplyJson(
        request,
        useId,
      ),
    ) as string,
    admitStoreUseCancellationReplyJson: (body: string, request: unknown, useId: string) => checked(
      moon.strategyRemoteTransferStoreUseCancellationReplyAdmitJson(
        body,
        request,
        useId,
      ),
    ),
    storeUseCancellationReplyProjection:
      moon.strategyRemoteTransferStoreUseCancellationReplyProjection,
    prepareDestinationReceipt: (request: unknown, materialGeneration: string) => checked(
      moon.strategyRemoteTransferDestinationReceiptPrepare(
        request,
        materialGeneration,
      ),
    ),
    destinationReceiptJson: (receipt: unknown) => checked(
      moon.strategyRemoteTransferDestinationReceiptJson(receipt),
    ) as string,
    destinationReceiptIdentity:
      moon.strategyRemoteTransferDestinationReceiptIdentity,
    admitDestinationReceiptJson: (body: string, request: unknown, claimedReceiptCid: string) =>
      checked(moon.strategyRemoteTransferDestinationReceiptAdmitJson(
        body,
        request,
        claimedReceiptCid,
      )) as DestinationReceipt,
    destinationReceiptProjection:
      moon.strategyRemoteTransferDestinationReceiptProjection,
    storeUse: Object.freeze({
      prepare: (request: unknown, useId: string) => checked(
        moon.strategyRemoteTransferStoreUsePrepare(request, useId),
      ),
      identity: moon.strategyRemoteTransferStoreUseIdentity,
      projection: moon.strategyRemoteTransferStoreUseProjection,
      open: moon.strategyRemoteTransferStoreUseOpen,
      prepareStart: (record: unknown) => checked(
        moon.strategyRemoteTransferStoreUseStartPrepare(record),
      ),
      prepareProgress: (record: unknown, confirmedChunks: number, confirmedBytes: Quantity) => checked(
        moon.strategyRemoteTransferStoreUseProgressPrepare(
          record,
          confirmedChunks,
          int64(confirmedBytes, 'confirmed Store use bytes'),
        ),
      ),
      prepareComplete: (record: unknown, receipt: unknown) => checked(
        moon.strategyRemoteTransferStoreUseCompletePrepare(record, receipt),
      ),
      prepareFailure: (record: unknown, readerStopped: boolean) => checked(
        moon.strategyRemoteTransferStoreUseFailurePrepare(
          record,
          readerStopped,
        ),
      ),
      prepareUnknown: (record: unknown) => checked(
        moon.strategyRemoteTransferStoreUseUnknownPrepare(record),
      ),
      prepareCleanup: (record: unknown) => checked(
        moon.strategyRemoteTransferStoreUseCleanupPrepare(record),
      ),
      transitionProjection: (transition: unknown) => tuplePair(
        moon.strategyRemoteTransferStoreUseTransitionProjection(transition),
      ) as ReturnType<CommonTransferBindings['strategyRemoteTransferStoreUseTransitionProjection']> | undefined,
      transitionKey:
        moon.strategyRemoteTransferStoreUseTransitionJournalKey,
      commitTransition: (transition: unknown, durable: boolean) => checked(
        moon.strategyRemoteTransferStoreUseTransitionCommit(
          transition,
          durable,
        ),
      ),
      recordProjection: moon.strategyRemoteTransferStoreUseRecordProjection,
      restore: (storeUse: unknown, state: unknown) => {
        if (!Array.isArray(state) || state.length !== 7 ||
            state.some(value => typeof value !== 'string') ||
            !/^(0|[1-9][0-9]*)$/.test(state[0]) ||
            !/^[0-4]$/.test(state[1]) || !/^[0-2]$/.test(state[2]) ||
            !/^(0|[1-9][0-9]*)$/.test(state[3]) ||
            !/^(0|[1-9][0-9]*)$/.test(state[4]) ||
            !/^[01]$/.test(state[5])) {
          throw new TypeError('Invalid Remote Transfer Store use state');
        }
        const revision = Number(state[0]);
        const confirmedChunks = Number(state[3]);
        if (!Number.isSafeInteger(revision) ||
            !Number.isSafeInteger(confirmedChunks)) {
          throw new TypeError('Invalid Remote Transfer Store use revision');
        }
        return checked(moon.strategyRemoteTransferStoreUseRecordRestore(
          storeUse,
          revision,
          Number(state[1]),
          Number(state[2]),
          confirmedChunks,
          BigInt(state[4]),
          state[5] === '1',
          state[6],
        ));
      },
    }),
    requestProjection: moon.strategyRemoteTransferProjection,
    journalKey: moon.strategyRemoteTransferJournalKey,
    chunks: (request: unknown) => {
      const cids = moon.strategyRemoteTransferChunkCids(request);
      const byteLengths = moon.strategyRemoteTransferChunkByteLengths(request);
      const rowCounts = moon.strategyRemoteTransferChunkRowCounts(request);
      if (cids.length !== byteLengths.length ||
          cids.length !== rowCounts.length) {
        throw new Error('Remote Transfer projection mismatch');
      }
      return Object.freeze(cids.map((cid, index) => Object.freeze({
        cid,
        byteLength: byteLengths[index],
        rowCount: rowCounts[index],
      })));
    },
    activeAt: (request: unknown, trustedNowMilliseconds: Quantity) => moon.strategyRemoteTransferActiveAt(
        request,
        int64(trustedNowMilliseconds, 'trusted clock'),
      ),
    open: moon.strategyRemoteTransferOpen,
    prepareStart: (value: unknown) => checked(
      moon.strategyRemoteTransferStartPrepare(value),
    ),
    prepareSourceSettled: (value: unknown, integrityVerified: boolean, objectSealed: boolean) => checked(
      moon.strategyRemoteTransferSourceSettledPrepare(
        value,
        integrityVerified,
        objectSealed,
      ),
    ),
    prepareDestinationCommit: (value: unknown) => checked(
      moon.strategyRemoteTransferDestinationCommitPrepare(value),
    ),
    prepareFailure: (value: unknown, cancelled: boolean, sourceAccessStopped: boolean) => checked(
      moon.strategyRemoteTransferFailurePrepare(
        value,
        cancelled,
        sourceAccessStopped,
      ),
    ),
    prepareUnknown: (value: unknown) => checked(
      moon.strategyRemoteTransferUnknownPrepare(value),
    ),
    prepareCleanup: (value: unknown, sourceAccessStopped: boolean, destinationTemporaryReclaimed: boolean, objectUseReleased: boolean) => checked(moon.strategyRemoteTransferCleanupPrepare(
      value,
      sourceAccessStopped,
      destinationTemporaryReclaimed,
      objectUseReleased,
    )),
    transitionProjection: (value: unknown) => tuplePair(
      moon.strategyRemoteTransferTransitionProjection(value),
    ) as ReturnType<CommonTransferBindings['strategyRemoteTransferTransitionProjection']> | undefined,
    transitionKey: moon.strategyRemoteTransferTransitionJournalKey,
    commitTransition: (value: unknown, durable: boolean) => checked(
      moon.strategyRemoteTransferTransitionCommit(value, durable),
    ),
    recordProjection: moon.strategyRemoteTransferRecordProjection,
    recordRequestIdentity:
      moon.strategyRemoteTransferRecordRequestIdentity,
    recordIsDestinationCommitted:
      moon.strategyRemoteTransferRecordIsDestinationCommitted,
    directCleanupConfirmed:
      moon.strategyRemoteTransferDirectCleanupConfirmed,
    directTransferProgress:
      moon.strategyRemoteTransferDirectProgress,
    directCancelDecision:
      moon.strategyRemoteTransferDirectCancelDecision,
    revision: moon.strategyRemoteTransferRecordRevision,
    restore: (request: unknown, state: unknown) => {
      if (!Array.isArray(state) || state.length !== 9 ||
          state.some(value => !Number.isSafeInteger(value))) {
        throw new TypeError('Invalid Remote Transfer state');
      }
      return checked(moon.strategyRemoteTransferRecordRestore(request, state));
    },
  });
}
