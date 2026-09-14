import { DuckDBTransportError } from './session.mjs';

// Host capacity policy for the bounded parameter/chunk representation. These
// allowances are not measured V8 heap bytes or an OS memory-limit guarantee.
// Transfer limits count serialized UTF-8 framing; allow simultaneous UTF-16 and
// serialization representations, plus bounded cell/column container capacity.
// A smaller future policy requires separate implementation/measurement evidence.
export function computePhysicalCapacity(limits) {
  for (const name of ['memoryBytes', 'maxTransportBytes', 'maxCells', 'maxColumns', 'maxParameters', 'maxSqlBytes']) {
    if (!Number.isSafeInteger(limits[name]) || limits[name] < (name === 'memoryBytes' ? 1 : 0)) {
      throw new DuckDBTransportError('InvalidLimits');
    }
  }
  const framing = BigInt(limits.maxTransportBytes) * 8n;
  const containers = (BigInt(limits.maxCells) + BigInt(limits.maxColumns) + BigInt(limits.maxParameters)) * 256n;
  const sql = BigInt(limits.maxSqlBytes) * 4n;
  const scratchBytes = framing + containers + sql;
  const executionBytes = BigInt(limits.memoryBytes) + scratchBytes;
  if (executionBytes > 9223372036854775807n) throw new DuckDBTransportError('InvalidLimits');
  return Object.freeze({
    databaseBytes: BigInt(limits.memoryBytes), scratchBytes, executionBytes,
    transferBytes: BigInt(limits.maxTransportBytes),
  });
}
