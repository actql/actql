// Physical transport for the existing family-owned snapshot operation. The
// common driver owns work, checked ports, source revocation and restored custody.
// This adapter neither interprets Graph records nor issues completion evidence.
import {createMoonBitRetainedRowFrames} from '../store-local/moonbit-row-frames.mjs';
const yieldToHost = () => new Promise(resolve => setTimeout(resolve, 0));
const quantum = 32;

const validateAdvance = observation => {
  if (!observation || typeof observation.complete !== 'boolean' ||
      typeof observation.work !== 'bigint' || observation.work < 0n ||
      observation.work > BigInt(quantum) ||
      typeof observation.progress !== 'bigint' || observation.progress < 0n ||
      (!observation.complete && observation.work === 0n)) {
    throw new Error('InvalidLocalSnapshotAdvance');
  }
  return observation;
};

export function prepareLocalCarrierSnapshot(operations, createLease, checked, signal) {
  return prepareLocalSnapshot(operations, createLease, checked, signal);
}

// Relation conversion uses the same installed Store custody and failure
// handle; only the common completion export/import operations differ.
export function prepareLocalRelationSnapshot(operations, createLease, checked, signal, moon) {
  return prepareLocalSnapshot(operations, createLease, checked, signal, moon);
}

function prepareLocalSnapshot(operations, createLease, checked, signal, moon) {
  const relation = moon !== undefined;
  const prepare = relation ? operations.prepare_relation_snapshot : operations.prepare_carrier_snapshot;
  if (typeof createLease !== 'function' ||
      typeof prepare !== 'function') {
    throw new TypeError('LocalSnapshotStoreRequired');
  }
  let store, body, released = true, started = false;
  let retrying;
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
      const operation = checked(prepare(() => released));
      if (operation == null) return undefined;
      const {key} = operation;
      const maximumBytes = relation ? operation.frames.maxBytes : operation.maximum_bytes;
      const maximumFrameBytes = relation ? operation.frames.maxFrameBytes : operation.maximum_frame_bytes;
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
        const observation = relation ? undefined : validateAdvance(checked(operation.advance_save(quantum)));
        const part = checked(relation ? operation.next() : operation.take_output());
        if (relation && part == null) break;
        if (typeof part !== 'string') throw new Error('InvalidLocalSnapshotFrame');
        if (part.length > maximumFrameBytes) throw new Error('LocalSnapshotByteLimit');
        const bytes = new TextEncoder().encode(part).byteLength;
        if (bytes > maximumFrameBytes || bytes > maximumBytes - emittedBytes) {
          throw new Error('LocalSnapshotByteLimit');
        }
        emittedBytes += bytes;
        if (bytes !== 0) await writer.append(part);
        if (observation?.complete) break;
        await yieldToHost();
      }
      const content = checked(operation.content());
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
        const sourceRows = operations.output_rows();
        checked(operation.release_source(body.cid, () => body.available()));
        if (operation.source_available() !== false) throw new Error('LocalRelationSourceStillAvailable');
        let sourceReadRejected = sourceRows === 0;
        if (sourceRows > 0) {
          try { checked(operations.output_row(0)); }
          catch { sourceReadRejected = true; }
        }
        if (!sourceReadRejected) throw new Error('LocalRelationSourceStillReadable');
        checked(operation.begin_reload());
        const frames = createMoonBitRetainedRowFrames({
          retainedFramesPrepare: moon.strategyPrepareDurableResultRowFrames,
          retainedFramesFeed: moon.strategyFeedDurableResultRowFrames,
          retainedFramesFinish: moon.strategyFinishDurableResultRowFrames,
          retainedFramesCancel: moon.strategyCancelDurableResultRowFrames,
        }, operation.frames, row => checked(operation.append_reload(row)));
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
          checked(operation.finish_reload());
        } finally { frames.cancel(); }
        await cleanupHandle.retry();
        if (!released) throw new Error('LocalSnapshotCleanupPending');
        signal?.throwIfAborted();
        checked(operation.finish());
        return Object.freeze({cid:content.cid,bytes:content.bytes,
          verifiedReadBytes:receivedBytes,rows:usage.rows,
          sourceReleased:true,sourceReadRejected,restored:true,temporaryBodyReclaimed:true});
      }
      checked(operation.release_source(body.cid));
      const decoder = new TextDecoder('utf-8', {fatal: true});
      const parts = [];
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
      checked(operation.begin_reload(parts.join(''), () => body.available()));
      parts.length = 0;
      for (;;) {
        signal?.throwIfAborted();
        const observation = validateAdvance(checked(operation.advance_reload(quantum)));
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
