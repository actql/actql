import {snapshotDataProfile} from './data-profile.mjs';

// Installed example-reader policy. Cumulative content limits belong to the
// application; decoding retains one bounded canonical row and frame at a time.
// This is a declared container/encoding allowance, not a V8 RSS guarantee.
export function retainedReaderPolicy(supplied) {
  const data = snapshotDataProfile(supplied);
  const columns = data?.columns ?? 10;
  const batchBytes = data?.batch_bytes ?? 100000;
  // Every JSON node occupies at least one input byte. A larger cumulative node
  // ceiling cannot authorize more simultaneous nodes in a single row frame.
  const nodes = Math.min(data?.value_nodes ?? 10000, batchBytes);
  return Object.freeze({
    columns,
    recordLimits: Object.freeze({maxCompletions: 4, maxInputs: 2, maxColumns: columns}),
    wire: Object.freeze({max_bytes: data?.wire_bytes ?? 100000,
      max_nodes: data?.value_nodes ?? 10000, max_depth: 64,
      max_columns: columns, max_order_work: data?.work ?? 10000}),
    frameLimits: Object.freeze({maxBytes: data?.wire_bytes ?? 100000,
      maxRows: data?.task_rows ?? 100, maxRowBytes: batchBytes, maxFrameBytes: batchBytes, maxDepth: 64}),
    decodeLimits: Object.freeze({max_bytes: batchBytes, max_nodes: nodes,
      max_depth: 64, max_text_bytes: batchBytes}),
    // Raw/decoded/admitted/encoder representations plus bounded metadata.
    scratchBytes: 2000000n + BigInt(batchBytes) * 32n + BigInt(nodes) * 1024n,
  });
}
