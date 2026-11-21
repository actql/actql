// Translate one authorized, owner-recorded JSONL delivery into typed Local
// frames. The canonical serializer and delivery attempt stay in MoonBit.
import {deliverAuthorizedResult} from './result-access.mjs';

type Delivery = Parameters<typeof deliverAuthorizedResult>;
type LocalReadRequest = Omit<Delivery[1], 'format'>;
type FrameLimits = Readonly<{maxRowBytes: number}>;
type LocalFrame = Readonly<{value: Record<string, unknown>; byteLength: number}>;
type CleanupPending = Readonly<{cleanupPending?: unknown}> | null | undefined;

const terminator = Uint8Array.of(0x1e);

export function authorizedLocalResultFrames(
  service: Delivery[0], request: LocalReadRequest, signal: Delivery[3], {maxRowBytes}: FrameLimits,
) {
  if (!Number.isSafeInteger(maxRowBytes) || maxRowBytes < 1 ||
      request === null || typeof request !== 'object' ||
      signal === null || signal !== undefined &&
        typeof signal.throwIfAborted !== 'function') {
    throw new TypeError('InvalidLocalResultFrameRequest');
  }
  return Object.freeze({kind: 'rows' as const, frames: Object.freeze({
    async *[Symbol.asyncIterator]() {
      const controller = new AbortController();
      const abort = () => controller.abort(signal!.reason);
      const channel = new TransformStream<Uint8Array, Uint8Array>({start(stream) {
        // A paused consumer can leave delivery awaiting backpressure. Abort
        // the owned channel as well as its signal so that write settles and
        // the delivery owner can release its physical reader and record its
        // outcome without requiring another consumer next/return call.
        controller.signal.addEventListener('abort', () =>
          stream.error(controller.signal.reason), {once: true});
      }},
        {highWaterMark: 1, size: bytes => bytes.byteLength},
        {highWaterMark: 1, size: bytes => bytes.byteLength});
      const writer = channel.writable.getWriter();
      const reader = channel.readable.getReader();
      signal?.addEventListener('abort', abort, {once: true});
      if (signal?.aborted) abort();
      const outcome = deliverAuthorizedResult(service,
        {...request, format: 'jsonl'}, {
          async write(bytes) {
            await writer.write(Uint8Array.from(bytes));
            return {confirmedBytes: bytes.byteLength};
          },
          async finish() {
            await writer.write(terminator);
            await writer.close();
            return {confirmed: true};
          },
        }, controller.signal).then(
        () => ({ok: true as const}),
        async (error: unknown) => {
          try { await writer.abort(error); } catch {}
          return {ok: false as const, error};
        },
      );
      const decoder = new TextDecoder('utf-8', {fatal: true});
      const encoder = new TextEncoder();
      let pending = '';
      let complete = false;
      try {
        while (true) {
          const {done, value} = await reader.read();
          if (done) break;
          pending += decoder.decode(value, {stream: true});
          let newline;
          while ((newline = pending.indexOf('\n')) >= 0) {
            const text = pending.slice(0, newline);
            pending = pending.slice(newline + 1);
            const byteLength = encoder.encode(text).byteLength;
            if (!text || byteLength > maxRowBytes) {
              throw new Error('InvalidLocalResultFrame');
            }
            const value: unknown = JSON.parse(text);
            if (value === null || typeof value !== 'object' ||
                Array.isArray(value)) {
              throw new Error('InvalidLocalResultFrame');
            }
            yield Object.freeze({value, byteLength}) as LocalFrame;
          }
          if (encoder.encode(pending).byteLength > maxRowBytes) {
            throw new Error('InvalidLocalResultFrame');
          }
        }
        pending += decoder.decode();
        if (pending !== '\x1e') {
          throw new Error('IncompleteLocalResultFrames');
        }
        complete = true;
        // Normal wire termination cannot hide a failure of the delivery
        // owner's terminal record or receipt custody transition.
        const settled = await outcome;
        if (!settled.ok) throw settled.error;
      } finally {
        signal?.removeEventListener('abort', abort);
        if (!complete) controller.abort();
        try { if (!complete) await reader.cancel(); } catch {}
        reader.releaseLock();
        const settled = await outcome;
        // Early return/abort still owns terminal-record durability. Preserve
        // its existing retry handle rather than swallowing that failure.
        if (!settled.ok && (settled.error as CleanupPending)?.cleanupPending === true) {
          throw settled.error;
        }
      }
    },
  })});
}
