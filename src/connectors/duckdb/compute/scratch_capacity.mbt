///|
/// Capacity for bounded MoonBit decoding, admitted batches and post-DB checks.
/// It remains reserved after native cleanup until completion/failed disposal.
pub fn duckdb_task_scratch_capacity(
  limits : DuckDBComputeLimits,
  transport : @duckdb.TransportColumnLimits,
) -> Int64? {
  let nodes = [
    transport.max_nodes,
    transport.max_columns,
    transport.max_rows,
    limits.physical.max_nodes,
    limits.physical.max_cells,
    limits.physical.max_rows,
    limits.values.max_nodes,
    limits.values.max_depth,
    limits.demand.max_nodes,
    limits.demand.max_depth,
    limits.retention.max_depth,
    limits.completion_entries,
  ]
  let texts = [
    transport.max_bytes,
    transport.max_text_bytes,
    limits.physical.max_text_bytes,
    limits.values.max_bytes,
    limits.demand.max_bytes,
    limits.completion_name_bytes,
  ]
  let mut bytes = 0L
  for count in nodes {
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
