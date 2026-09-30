// Pure profile validation. Keep byte/count values exact across the MoonBit-to-JS boundary.
export function snapshotDataProfile(value) {
  if (value === undefined) return undefined;
  const keys = ['source_rows', 'task_rows', 'columns', 'value_bytes', 'wire_bytes',
    'value_nodes', 'text_bytes', 'work', 'entries', 'batch_bytes'];
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).sort().join(',') !== [...keys].sort().join(',')) {
    throw new TypeError('InvalidApplicationDataProfile');
  }
  const data = Object.fromEntries(keys.map(key => [key, value[key]]));
  if (Object.values(data).some(item => !Number.isSafeInteger(item) || item <= 0 || item > 2147483647) ||
      data.columns > 256 || data.wire_bytes > 715827882 || data.batch_bytes > data.wire_bytes ||
      (data.source_rows + data.task_rows) * data.columns > 2147483647) {
    throw new TypeError('InvalidApplicationDataProfile');
  }
  return Object.freeze(data);
}
