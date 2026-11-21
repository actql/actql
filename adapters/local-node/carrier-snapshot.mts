// Physical transport for the existing family-owned snapshot operation. The
// common driver owns work, checked ports, source revocation and restored custody.
// This adapter neither interprets Graph records nor issues completion evidence.
import {createMoonBitRetainedRowFrames} from '../store-local/moonbit-row-frames.mjs';
import type {RetainedRowFrameLimits} from '../store-local/row-frames.mjs';
import type {readLocalRetainedInput} from './retained-input.mjs';
import type {prepareLocalRetainedOutput} from './retained-output.mjs';
import type {LeasedOutputBody, LocalStoreLease, LocalStoreLeaseFactory} from './retained-store.mjs';

type Check = Parameters<typeof prepareLocalRetainedOutput>[2];
type FrameBindings = Parameters<typeof readLocalRetainedInput>[0];
type SnapshotAdvance = Readonly<{complete: boolean; work: bigint; progress: bigint}>;
type ContentIdentity = Readonly<{cid: string; bytes: number}>;
type Prepare = (released: () => boolean) => unknown;
type CarrierPorts = Readonly<{prepare_carrier_snapshot: Prepare}>;
type RelationPorts = Readonly<{
  prepare_relation_snapshot: Prepare;
  output_rows(): number;
  output_row(index: number): unknown;
}>;
type SnapshotOperation = Readonly<{
  key: string;
  advance_save(quantum: number): unknown;
  take_output(): unknown;
  content(): unknown;
  finish(): unknown;
}>;
type CarrierOperation = SnapshotOperation & Readonly<{
  maximum_bytes: number;
  maximum_frame_bytes: number;
  release_source(cid: string): unknown;
  begin_reload(text: string, available: () => boolean): unknown;
  advance_reload(quantum: number): unknown;
}>;
type RelationOperation = SnapshotOperation & Readonly<{
  frames: RetainedRowFrameLimits;
  release_source(cid: string, available: () => boolean): unknown;
  source_available(): boolean;
  begin_reload(): unknown;
  append_reload(row: string): unknown;
  finish_reload(): unknown;
  cleanup_references?(quantum: number): unknown;
}>;
const yieldToHost = () => new Promise<void>(resolve =>
  typeof setImmediate === 'function' ? setImmediate(resolve) : setTimeout(resolve, 0));
const quantum = 32;

const validateAdvance = (observation: SnapshotAdvance | null | undefined, bufferedOutput = false) => {
  if (!observation || typeof observation.complete !== 'boolean' ||
      typeof observation.work !== 'bigint' || observation.work < 0n ||
      observation.work > BigInt(quantum) ||
      typeof observation.progress !== 'bigint' || observation.progress < 0n ||
      (!observation.complete && observation.work === 0n && !bufferedOutput)) {
    throw new Error('InvalidLocalSnapshotAdvance');
  }
  return observation;
};

export function prepareLocalCarrierSnapshot(operations: CarrierPorts,
  createLease: LocalStoreLeaseFactory | undefined, checked: Check, signal?: AbortSignal) {
  return prepareLocalSnapshot(operations, createLease, checked, signal);
}

// Relation conversion uses the same installed Store custody and failure
// handle; only the common completion export/import operations differ.
export function prepareLocalRelationSnapshot(operations: RelationPorts, createLease: LocalStoreLeaseFactory | undefined,
  checked: Check, signal: AbortSignal | undefined, moon: FrameBindings) {
  return prepareLocalSnapshot(operations, createLease, checked, signal, moon);
}

function prepareLocalSnapshot(operations: Partial<CarrierPorts & RelationPorts>, createLease: LocalStoreLeaseFactory | undefined,
  checked: Check, signal?: AbortSignal, moon?: FrameBindings) {
  const relation = moon !== undefined;
  const prepare = relation ? operations.prepare_relation_snapshot : operations.prepare_carrier_snapshot;
  if (typeof createLease !== 'function' ||
      typeof prepare !== 'function') {
    throw new TypeError('LocalSnapshotStoreRequired');
  }
  let store: LocalStoreLease | undefined, body: LeasedOutputBody | undefined, released = true, started = false;
  let retrying: Promise<void> | undefined;
  const close = () => { body?.close(); store?.close(); };
  const reclaim = async () => {
    if (!store || released) return;
    close();
    // A process lease's local close is NOT release of its parent's holding.
    // Its exact typed release report is required; never infer it from zero
    // local usage or elapsed time. Ordinary file Stores own physical cleanup.
    if (typeof store.release === 'function') {
      await store.cleanup();
      const result = await store.release();
      if (!result || typeof result.pending !== 'boolean') {
        throw new Error('InvalidLocalSnapshotRelease');
      }
      released = !result.pending;
    } else {
      await store.cleanup();
      const state = store.status();
      released = state?.reservedBytes === 0 && state?.cleanupPending === false;
    }
  };
  const cleanupHandle = Object.freeze({
    status: () => Object.freeze({pending: !released}),
    async retry() {
      if (!retrying) retrying = reclaim().finally(() => { retrying = undefined; });
      await retrying;
      return cleanupHandle.status();
    },
  });
  return Object.freeze({
    close,
    cleanupHandle,
    async roundtrip() {
      if (started) throw new Error('LocalSnapshotAlreadyStarted');
      started = true;
      signal?.throwIfAborted();
      // Bind release observation before any Store allocation. None means this
      // Carrier has no installed persistence operation, not a tuple fallback.
      const operation = checked(prepare(() => released)) as CarrierOperation | RelationOperation | null | undefined;
      if (operation == null) return undefined;
      const {key} = operation;
      const maximumBytes = relation ? (operation as RelationOperation).frames.maxBytes : (operation as CarrierOperation).maximum_bytes;
      const maximumFrameBytes = relation ? (operation as RelationOperation).frames.maxFrameBytes : (operation as CarrierOperation).maximum_frame_bytes;
      if (typeof key !== 'string' || key.length === 0 || key.length > 256 ||
          !Number.isSafeInteger(maximumBytes) || maximumBytes < 1 ||
          !Number.isSafeInteger(maximumFrameBytes) || maximumFrameBytes < 1 ||
          maximumFrameBytes > maximumBytes || maximumFrameBytes > 16777216) {
        throw new Error('InvalidLocalSnapshotLimits');
      }
      store = await createLease(key, maximumBytes, maximumFrameBytes, signal);
      // A rejected factory has not transferred a lease to this owner. Start
      // cleanup responsibility only after acquisition, before any Store use.
      released = false;
      signal?.throwIfAborted();
      const writer = store.reserve(maximumBytes);
      await writer.start();
      let emittedBytes = 0;
      for (;;) {
        signal?.throwIfAborted();
        const advanced = checked(operation.advance_save(quantum)) as SnapshotAdvance | null | undefined;
        if (!relation) validateAdvance(advanced);
        signal?.throwIfAborted();
        const part = checked(operation.take_output());
        // A bounded Relation poll may drain already-admitted buffered bytes
        // before entering another row transition. Empty zero-work polls still
        // fail; physical output is never invented to make progress.
        const observation = relation ? validateAdvance(advanced,
          typeof part === 'string' && part.length > 0) : advanced;
        if (typeof part !== 'string') throw new Error('InvalidLocalSnapshotFrame');
        if (part.length > maximumFrameBytes) throw new Error('LocalSnapshotByteLimit');
        const bytes = new TextEncoder().encode(part).byteLength;
        if (bytes > maximumFrameBytes || bytes > maximumBytes - emittedBytes) {
          throw new Error('LocalSnapshotByteLimit');
        }
        emittedBytes += bytes;
        if (bytes !== 0) {
          await writer.append(part);
          signal?.throwIfAborted();
        }
        if (observation?.complete) break;
        await yieldToHost();
      }
      const content = checked(operation.content()) as ContentIdentity | null | undefined;
      if (!content || content.bytes !== emittedBytes ||
          typeof content.cid !== 'string' || !/^sha256:[0-9a-f]{64}$/.test(content.cid)) {
        throw new Error('InvalidLocalSnapshotContent');
      }
      signal?.throwIfAborted();
      body = await writer.seal(content);
      if (!body || body.cid !== content.cid || body.bytes !== content.bytes ||
          body.available() !== true) throw new Error('LocalSnapshotIdentityMismatch');
      signal?.throwIfAborted();
      if (relation) {
        const sourceRows = operations.output_rows!();
        checked((operation as RelationOperation).release_source(body.cid, () => body!.available()));
        if ((operation as RelationOperation).source_available() !== false) throw new Error('LocalRelationSourceStillAvailable');
        let sourceReadRejected = sourceRows === 0;
        if (sourceRows > 0) {
          try { checked(operations.output_row!(0)); }
          catch { sourceReadRejected = true; }
        }
        if (!sourceReadRejected) throw new Error('LocalRelationSourceStillReadable');
        checked((operation as RelationOperation).begin_reload());
        signal?.throwIfAborted();
        // The SAME sealed content bounds this receiving constructor. Common
        // has already reserved its reload geometry from this exact receipt;
        // a broader policy ceiling is not an eagerly allocated row buffer.
        const reloadFrames = {...(operation as RelationOperation).frames,
          maxBytes: Math.min((operation as RelationOperation).frames.maxBytes, content.bytes),
          maxRowBytes: Math.min((operation as RelationOperation).frames.maxRowBytes, content.bytes)};
        const frames = createMoonBitRetainedRowFrames({
          retainedFramesPrepare: moon.strategyPrepareDurableResultRowFrames,
          retainedFramesFeed: moon.strategyFeedDurableResultRowFrames,
          retainedFramesFinish: moon.strategyFinishDurableResultRowFrames,
          retainedFramesCancel: moon.strategyCancelDurableResultRowFrames,
        }, reloadFrames, row => checked((operation as RelationOperation).append_reload(row)));
        let receivedBytes = 0;
        let usage;
        try {
          await body.consume(async bytes => {
            signal?.throwIfAborted();
            if (!(bytes instanceof Uint8Array) || bytes.byteLength < 1 ||
                bytes.byteLength > maximumFrameBytes ||
                bytes.byteLength > maximumBytes - receivedBytes) {
              throw new Error('InvalidLocalSnapshotRead');
            }
            receivedBytes += bytes.byteLength;
            await frames.feed(bytes, signal);
          }, signal);
          usage = frames.finish();
          if (receivedBytes !== content.bytes || usage.bytes !== receivedBytes) {
            throw new Error('LocalSnapshotReadIncomplete');
          }
          signal?.throwIfAborted();
          checked((operation as RelationOperation).finish_reload());
        } finally { frames.cancel(); }
        await cleanupHandle.retry();
        if (!released) throw new Error('LocalSnapshotCleanupPending');
        if (typeof (operation as RelationOperation).cleanup_references !== 'function') {
          throw new Error('LocalRelationSnapshotCleanupRequired');
        }
        for (;;) {
          signal?.throwIfAborted();
          const complete = (operation as RelationOperation).cleanup_references!(quantum);
          if (typeof complete !== 'boolean') {
            throw new Error('InvalidLocalRelationSnapshotCleanup');
          }
          if (complete) break;
          await yieldToHost();
        }
        signal?.throwIfAborted();
        checked(operation.finish());
        return Object.freeze({cid:content.cid,bytes:content.bytes,
          verifiedReadBytes:receivedBytes,rows:usage.rows,
          sourceReleased:true,sourceReadRejected,restored:true,temporaryBodyReclaimed:true});
      }
      checked((operation as CarrierOperation).release_source(body.cid));
      const decoder = new TextDecoder('utf-8', {fatal: true});
      const parts: string[] = [];
      let receivedBytes = 0;
      // Chunks are provisional. Neither family admission nor task completion
      // runs until consume verifies the full sealed body and confirms read end.
      await body.consume(bytes => {
        signal?.throwIfAborted();
        if (!(bytes instanceof Uint8Array) || bytes.byteLength < 1 ||
            bytes.byteLength > maximumFrameBytes ||
            bytes.byteLength > maximumBytes - receivedBytes) {
          throw new Error('InvalidLocalSnapshotRead');
        }
        receivedBytes += bytes.byteLength;
        parts.push(decoder.decode(bytes, {stream: true}));
      }, signal);
      parts.push(decoder.decode());
      if (receivedBytes !== content.bytes) throw new Error('LocalSnapshotReadIncomplete');
      signal?.throwIfAborted();
      checked((operation as CarrierOperation).begin_reload(parts.join(''), () => body!.available()));
      parts.length = 0;
      for (;;) {
        signal?.throwIfAborted();
        const observation = validateAdvance(checked((operation as CarrierOperation).advance_reload(quantum)) as SnapshotAdvance);
        if (observation.complete) break;
        await yieldToHost();
      }
      signal?.throwIfAborted();
      await cleanupHandle.retry();
      if (!released) throw new Error('LocalSnapshotCleanupPending');
      signal?.throwIfAborted();
      checked(operation.finish());
      return Object.freeze({cid: content.cid, bytes: content.bytes,
        verifiedReadBytes: receivedBytes, sourceReleased: true, restored: true,
        temporaryBodyReclaimed: true});
    },
  });
}
