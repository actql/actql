import { DuckDBTransportError, validateLimits } from './configuration.mjs';
import {boundedTransport, maxNativeVectorRows} from './transport-bounds.mjs';

// Reuse the selected receiver's real per-frame window in BOTH the quote and
// Session. Cumulative rows/cells/bytes and tighter explicit batches stay intact.
export function sourceTransportLimits(limits, maxChunkRows, maxChunkBytes) {
  limits = validateLimits(limits);
  // A zero cumulative budget keeps its existing refusal/empty-input path;
  // there is no positive batch window to invent or reserve for it.
  if (limits.maxRows === 0 || limits.maxTransportBytes === 0) return limits;
  if (![maxChunkRows, maxChunkBytes].every(value => Number.isSafeInteger(value) && value > 0)) {
    throw new DuckDBTransportError('InvalidLimits');
  }
  return Object.freeze({...limits,
    maxChunkRows: Math.min(limits.maxChunkRows ?? maxChunkRows, maxChunkRows, limits.maxRows),
    maxChunkBytes: Math.min(limits.maxChunkBytes ?? maxChunkBytes, maxChunkBytes, limits.maxTransportBytes)});
}

// Host capacity policy for the bounded parameter/chunk representation. These
// allowances are not measured V8 heap bytes or an OS memory-limit guarantee.
// Transfer limits count serialized UTF-8 framing; allow simultaneous UTF-16 and
// serialization representations, plus bounded cell/column container capacity.
// Bounded mode also requires pre-decode variable-width checks in session.mjs.
export function computePhysicalCapacity(limits) {
  limits = validateLimits(limits);
  let framing = BigInt(limits.maxTransportBytes) * 8n;
  let cells = BigInt(limits.maxCells);
  if (boundedTransport(limits)) {
    // Encoded/decoded/escaped current frames, including one provisional cell.
    // UTF-8 string lengths are checked before SDK decoding; parameter and
    // metadata frames are bounded before native binding/result consumption.
    framing = BigInt(limits.maxChunkBytes) * 32n;
    const delivered = BigInt(limits.maxChunkRows) * BigInt(limits.maxColumns);
    cells = (cells < delivered ? cells : delivered) +
      BigInt(maxNativeVectorRows) * BigInt(limits.maxColumns);
  }
  const containers = (cells + BigInt(limits.maxColumns) + BigInt(limits.maxParameters)) * 256n;
  const sql = BigInt(limits.maxSqlBytes) * 4n;
  const scratchBytes = framing + containers + sql;
  const executionBytes = BigInt(limits.memoryBytes) + scratchBytes;
  if (executionBytes > 9223372036854775807n) throw new DuckDBTransportError('InvalidLimits');
  return Object.freeze({
    databaseBytes: BigInt(limits.memoryBytes), scratchBytes, executionBytes,
    transferBytes: BigInt(limits.maxTransportBytes),
  });
}
