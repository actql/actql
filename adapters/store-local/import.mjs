import { createRetainedRowFrames } from './row-frames.mjs';
import { checked } from '../host-common/runtime-result.mjs';

const runtimeUrl = new URL('../../_build/js/release/build/retained_host_bridge/retained_host_bridge.js', import.meta.url);
let runtime;

// Trusted adapter assembly, not an execution-option verifier. consume must
// verify the exact source binding and complete file integrity before resolving.
// The common import independently verifies the entire ordered logical identity.
export async function importRetainedRows(source, consume, options, signal) {
  const snapshot = Object.freeze({
    maxRows: options.maxRows, maxBatchBytes: options.maxBatchBytes,
    values: Object.freeze({ ...options.values }),
    wire: Object.freeze({ ...options.wire }),
    row: Object.freeze({ ...options.row }),
    frames: Object.freeze({ ...options.frames }),
  });
  const integer = value => Number.isInteger(value) && value >= 0 && value <= 2147483647;
  if (!integer(snapshot.maxRows) || !integer(snapshot.maxBatchBytes) || typeof consume !== 'function') {
    throw new TypeError('InvalidRetainedImportLimits');
  }
  for (const [group, keys] of [
    [snapshot.values, ['max_nodes', 'max_text_bytes', 'max_depth', 'max_work']],
    [snapshot.wire, ['max_bytes', 'max_nodes', 'max_depth', 'max_columns', 'max_order_work']],
    [snapshot.row, ['max_bytes', 'max_nodes', 'max_depth', 'max_text_bytes']],
  ]) {
    if (keys.some(key => !integer(group[key]))) throw new TypeError('InvalidRetainedImportLimits');
  }
  signal?.throwIfAborted();
  const moon = await (runtime ??= import(runtimeUrl.href));
  signal?.throwIfAborted();
  let conversion;
  try {
    const frames = createRetainedRowFrames(snapshot.frames, row => {
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
