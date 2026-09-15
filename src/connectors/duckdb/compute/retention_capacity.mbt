///|
/// Declared Host container/encoding capacity, not observed process heap bytes.
/// Bounds come from the immutable admission and completion limits actually used.
pub fn duckdb_task_retention_capacity(limits : DuckDBComputeLimits) -> Int64? {
  let counts = [
    limits.retention.max_nodes,
    limits.physical.max_rows,
    limits.completion_entries,
  ]
  let texts = [limits.retention.max_text_bytes, limits.completion_name_bytes]
  let mut bytes = 0L
  for count in counts {
    if count < 0 {
      return None
    }
    bytes += count.to_int64() * 256L
  }
  for count in texts {
    if count < 0 {
      return None
    }
    bytes += count.to_int64() * 8L
  }
  Some(bytes)
}
