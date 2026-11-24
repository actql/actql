import {createMoonBitRetainedRowFrames} from './moonbit-row-frames.mjs';
import type {MoonBitRetainedFrameBindings} from './moonbit-row-frames.mjs';
import type {RetainedRowFrameLimits} from './row-frames.mjs';
import { checked } from '../host-common/runtime-result.mjs';

type ValueLimits = Readonly<Record<'max_nodes' | 'max_text_bytes' | 'max_depth' | 'max_work', number>>;
type WireLimits = Readonly<Record<'max_bytes' | 'max_nodes' | 'max_depth' | 'max_columns' | 'max_order_work', number>>;
type RowLimits = Readonly<Record<'max_bytes' | 'max_nodes' | 'max_depth' | 'max_text_bytes', number>>;
type RetainedImportLimits = Readonly<{
  maxRows: number;
  maxBatchBytes: number;
  values: ValueLimits;
  wire: WireLimits;
  row: RowLimits;
  frames: RetainedRowFrameLimits;
}>;
type RetainedImportBindings = MoonBitRetainedFrameBindings & Readonly<{
  retainedImportBegin(source: unknown, maxRows: number, values: ValueLimits, wire: WireLimits, maxBatchBytes: number): unknown;
  retainedImportAppend(conversion: unknown, row: string, limits: RowLimits): unknown;
  retainedImportFinish(conversion: unknown): unknown;
  retainedImportCancel(conversion: unknown): boolean;
}>;
type ConsumeRetainedBytes = (accept: (bytes: Uint8Array) => Promise<void>, signal?: AbortSignal) => unknown;

const runtimeUrl = new URL('../../_build/js/release/build/retained_host_bridge/retained_host_bridge.js', import.meta.url);
let runtime: Promise<RetainedImportBindings> | undefined;

// Trusted adapter assembly, not an execution-option verifier. consume must
// verify the exact source binding and complete file integrity before resolving.
// The common import independently verifies the entire ordered logical identity.
export async function importRetainedRows(source: unknown, consume: ConsumeRetainedBytes,
  options: RetainedImportLimits, signal?: AbortSignal) {
  const snapshot = Object.freeze({
    maxRows: options.maxRows, maxBatchBytes: options.maxBatchBytes,
    values: Object.freeze({ ...options.values }),
    wire: Object.freeze({ ...options.wire }),
    row: Object.freeze({ ...options.row }),
    frames: Object.freeze({ ...options.frames }),
  });
  const integer = (value: number) => Number.isInteger(value) && value >= 0 && value <= 2147483647;
  if (!integer(snapshot.maxRows) || !integer(snapshot.maxBatchBytes) || typeof consume !== 'function') {
    throw new TypeError('InvalidRetainedImportLimits');
  }
  for (const [group, keys] of [
    [snapshot.values, ['max_nodes', 'max_text_bytes', 'max_depth', 'max_work']],
    [snapshot.wire, ['max_bytes', 'max_nodes', 'max_depth', 'max_columns', 'max_order_work']],
    [snapshot.row, ['max_bytes', 'max_nodes', 'max_depth', 'max_text_bytes']],
  ] as readonly (readonly [Readonly<Record<string, number>>, readonly string[]])[]) {
    if (keys.some(key => !integer(group[key]))) throw new TypeError('InvalidRetainedImportLimits');
  }
  signal?.throwIfAborted();
  const moon = await (runtime ??= import(runtimeUrl.href));
  signal?.throwIfAborted();
  let conversion: unknown;
  try {
    const frames = createMoonBitRetainedRowFrames(moon, snapshot.frames, row => {
      checked(moon.retainedImportAppend(conversion, row, snapshot.row));
    });
    conversion = checked(moon.retainedImportBegin(source, snapshot.maxRows,
      snapshot.values, snapshot.wire, snapshot.maxBatchBytes));
    await consume(bytes => frames.feed(bytes, signal), signal);
    signal?.throwIfAborted();
    frames.finish();
    return checked(moon.retainedImportFinish(conversion));
  } catch (error) {
    if (conversion !== undefined) moon.retainedImportCancel(conversion);
    throw error;
  }
}
