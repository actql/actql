import {checked} from '../host-common/runtime-result.mjs';

const integer = value => Number.isSafeInteger(value) && value >= 0;

// Async environment bridge for the portable MoonBit row framer. The bridge
// owns callback sequencing only; all structure, capacity, and terminal-state
// decisions belong to the MoonBit parser.
export function createMoonBitRetainedRowFrames(moon, limits, accept) {
  if (moon === null || typeof moon !== 'object' ||
      typeof moon.retainedFramesPrepare !== 'function' ||
      typeof moon.retainedFramesFeed !== 'function' ||
      typeof moon.retainedFramesFinish !== 'function' ||
      typeof moon.retainedFramesCancel !== 'function' ||
      limits === null || typeof limits !== 'object' ||
      !integer(limits.maxBytes) || !integer(limits.maxRows) ||
      !integer(limits.maxRowBytes) || !integer(limits.maxDepth) ||
      !integer(limits.maxFrameBytes) || typeof accept !== 'function') {
    throw new TypeError('InvalidRetainedRowFrames');
  }
  const frames = checked(moon.retainedFramesPrepare(
    limits.maxBytes,
    limits.maxRows,
    limits.maxRowBytes,
    limits.maxDepth,
    limits.maxFrameBytes,
  ));
  let feeding = false;
  let closed = false;
  const cancel = () => {
    if (closed) return false;
    closed = true;
    moon.retainedFramesCancel(frames);
    return true;
  };
  return Object.freeze({
    async feed(chunk, signal) {
      if (closed || feeding) {
        throw new TypeError('InvalidRetainedRowFrame');
      }
      if (!(chunk instanceof Uint8Array)) {
        cancel();
        throw new TypeError('InvalidRetainedRowFrame');
      }
      feeding = true;
      try {
        signal?.throwIfAborted();
        const rows = checked(moon.retainedFramesFeed(frames, chunk));
        if (!Array.isArray(rows) || rows.some(row => typeof row !== 'string')) {
          throw new TypeError('InvalidRetainedRowFrameResult');
        }
        for (const row of rows) {
          signal?.throwIfAborted();
          await accept(row);
        }
        signal?.throwIfAborted();
      } catch (error) {
        cancel();
        throw error;
      } finally {
        feeding = false;
      }
    },
    finish() {
      if (closed || feeding) {
        throw new TypeError('InvalidRetainedRowFrameState');
      }
      closed = true;
      const summary = checked(moon.retainedFramesFinish(frames));
      if (!Array.isArray(summary) || summary.length !== 2 ||
          summary.some(value => !integer(value))) {
        throw new TypeError('InvalidRetainedRowFrameSummary');
      }
      return Object.freeze({bytes: summary[0], rows: summary[1]});
    },
    cancel,
  });
}
