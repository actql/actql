import {checked} from '../host-common/runtime-result.mjs';

import type {RetainedRowFrameLimits} from './row-frames.mjs';

export type MoonBitRetainedFrameBindings = Readonly<{
  retainedFramesPrepare(maxBytes: number, maxRows: number, maxRowBytes: number,
    maxDepth: number, maxFrameBytes: number): unknown;
  retainedFramesFeed(frames: unknown, chunk: Uint8Array): unknown;
  retainedFramesFinish(frames: unknown): unknown;
  retainedFramesCancel(frames: unknown): void;
}>;
type FrameReader = Readonly<{
  feed(chunk: unknown, signal?: AbortSignal): Promise<void>;
  finish(): Readonly<{bytes: number; rows: number}>;
  cancel(): boolean;
}>;
type RowConsumer = (row: string) => unknown;
type RowBatchConsumer = (rows: string[]) => unknown;

const integer = (value: unknown): value is number =>
  Number.isSafeInteger(value) && (value as number) >= 0 && (value as number) <= 2147483647;

// Async environment bridge for the portable MoonBit row framer. The bridge
// owns callback sequencing only; all structure, capacity, and terminal-state
// decisions belong to the MoonBit parser.
// `accept` receives each framed row. With `{batch: true}` it instead receives
// the complete rows framed from one fed chunk, in order, as one array.
export function createMoonBitRetainedRowFrames(moon: MoonBitRetainedFrameBindings,
  limits: RetainedRowFrameLimits, accept: RowConsumer, options?: {batch?: false}): FrameReader;
export function createMoonBitRetainedRowFrames(moon: MoonBitRetainedFrameBindings,
  limits: RetainedRowFrameLimits, accept: RowBatchConsumer, options: {batch: true}): FrameReader;
export function createMoonBitRetainedRowFrames(moon: MoonBitRetainedFrameBindings,
  limits: RetainedRowFrameLimits, accept: RowConsumer | RowBatchConsumer, {batch = false} = {}): FrameReader {
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
    async feed(chunk: unknown, signal?: AbortSignal) {
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
        if (batch) {
          if (rows.length) {
            const accepted = (accept as RowBatchConsumer)(rows);
            if (accepted && typeof (accepted as {then?: unknown}).then === 'function') await accepted;
          }
        } else {
          for (const row of rows) {
            signal?.throwIfAborted();
            const accepted = (accept as RowConsumer)(row as string);
            if (accepted && typeof (accepted as {then?: unknown}).then === 'function') await accepted;
          }
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
      return Object.freeze({bytes: summary[0] as number, rows: summary[1] as number});
    },
    cancel,
  });
}
