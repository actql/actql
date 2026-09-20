// Benchmark-owned physical capacity policy for the independent comparator.
// It mirrors the registered managed example's half-DB policy without importing
// product Host, planner, or DAG assembly.
const nativeVectorRows = 2048n;
const deliveredChunkRows = 128n;

export function equivalentExecutionCapacity(fixture) {
  const limits = fixture?.limits;
  if (!limits || !Number.isSafeInteger(limits.executionMemoryBytes) ||
      limits.executionMemoryBytes < 2 ||
      !Number.isSafeInteger(limits.batchBytes) || limits.batchBytes <= 0 ||
      !Number.isSafeInteger(limits.intermediateRows) ||
      limits.intermediateRows <= 0 ||
      !Number.isSafeInteger(limits.maxColumns) || limits.maxColumns <= 0) {
    throw new TypeError('InvalidEquivalentCapacityInput');
  }
  const limitBytes = BigInt(limits.executionMemoryBytes);
  const databaseBytes = limitBytes / 2n;
  const columns = BigInt(limits.maxColumns);
  const deliveredRows = BigInt(Math.min(
    limits.intermediateRows,
    Number(deliveredChunkRows),
  ));
  // Current encoded/decoded/escaped frames, the bounded delivered arrays, the
  // SDK's one native vector, field containers, and one bounded SQL string.
  const frameBytes = BigInt(limits.batchBytes) * 32n;
  const containerBytes = (
    (deliveredRows + nativeVectorRows) * columns + columns
  ) * 256n;
  const sqlBytes = BigInt(limits.batchBytes) * 4n;
  const scratchBytes = frameBytes + containerBytes + sqlBytes;
  const admittedBytes = databaseBytes + scratchBytes;
  if (admittedBytes > limitBytes) {
    throw new RangeError('EquivalentExecutionCapacityExceeded');
  }
  return Object.freeze({
    limitBytes,
    databaseBytes,
    scratchBytes,
    admittedBytes,
    maxChunkRows: Number(deliveredChunkRows),
    maxSqlBytes: limits.batchBytes,
  });
}
