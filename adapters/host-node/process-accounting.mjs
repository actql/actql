// Private local-IPC accounting, not ActQL identity or completion evidence.
// Exact primitive fields are copied before an await; no provider payload lives
// here. The common MoonBit ledger enforces cumulative relationships and limits.
const counts = ['planning_work', 'attempts', 'holdings'];
const limitBytes = ['transfer_bytes', 'retained_bytes', 'execution_bytes'];
const usageBytes = ['transferred_bytes', 'uncertain_transfer_bytes', 'reserved_transfer_bytes', 'held_bytes',
  'reserved_retention_bytes', 'reserved_execution_bytes', 'peak_retention_bytes'];
function copy(value, bytes, wire) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).sort().join(',') !== [...counts, ...bytes].sort().join(',')) {
    throw new TypeError('InvalidProcessAccounting');
  }
  const result = {};
  for (const key of counts) {
    const item = value[key];
    if (!Number.isInteger(item) || item < 0 || item > 2147483647) throw new TypeError('InvalidProcessAccounting');
    result[key] = item;
  }
  for (const key of bytes) {
    let item = value[key];
    if (wire) {
      if (typeof item !== 'string' || !/^(0|[1-9]\d{0,18})$/.test(item)) throw new TypeError('InvalidProcessAccounting');
      item = BigInt(item);
    }
    if (typeof item !== 'bigint' || item < 0n || item > 9223372036854775807n) throw new TypeError('InvalidProcessAccounting');
    result[key] = item;
  }
  return Object.freeze(result);
}
const encode = value => Object.freeze(Object.fromEntries(Object.entries(value)
  .map(([key, item]) => [key, typeof item === 'bigint' ? item.toString() : item])));
export const snapshotProcessLimits = value => copy(value, limitBytes, false);
export const encodeProcessLimits = value => encode(snapshotProcessLimits(value));
export const decodeProcessLimits = value => copy(value, limitBytes, true);
export const encodeProcessUsage = value => encode(copy(value, usageBytes, false));
export const decodeProcessUsage = value => copy(value, usageBytes, true);
export const emptyProcessUsage = () => Object.freeze(Object.fromEntries([
  ...counts.map(key => [key, 0]), ...usageBytes.map(key => [key, 0n]),
]));
