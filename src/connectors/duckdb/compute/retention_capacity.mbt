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

///|
/// The run reserves the whole DuckDB buffer-manager allowance once. This
/// bounded per-table planning allowance uses the admitted result shape instead
/// of cumulative Host value work, which may count many passes over one table.
/// It is a suballocation policy, not a measurement or a process RSS bound.
pub fn duckdb_resident_table_allowance(limits : DuckDBComputeLimits) -> Int64? {
  let physical = limits.physical
  if physical.max_rows < 0 ||
    physical.max_cells < 0 ||
    physical.max_text_bytes < 0 {
    return None
  }
  Some(
    1048576L +
    physical.max_rows.to_int64() * 64L +
    physical.max_cells.to_int64() * 64L +
    physical.max_text_bytes.to_int64() * 2L,
  )
}

///|
/// Completed streamed output retains metadata, not the admitted value table.
/// Storage bytes are added separately by the selected representation contract.
pub fn duckdb_stream_retention_capacity(limits : DuckDBComputeLimits) -> Int64? {
  guard duckdb_task_retention_capacity(limits) is Some(_) &&
    limits.metadata_work >= 0 else {
    return None
  }
  Some(
    (limits.completion_entries.to_int64() + limits.metadata_work.to_int64()) *
    256L +
    limits.completion_name_bytes.to_int64() * 8L,
  )
}

///|
/// Without an exact plan, or with value-sensitive join preflight, preserve the
/// full-input allowance. A streamed plan without retained join keys needs only
/// bounded transport/admission/encoding frames and completion metadata.
pub fn duckdb_stream_scratch_capacity(
  limits : DuckDBComputeLimits,
  transport : @duckdb.TransportColumnLimits,
  compute? : @duckdb.FixedCompute,
) -> Int64? {
  stream_scratch_capacity(
    limits,
    transport,
    compute is Some(_),
    compute.map(@duckdb.fixed_compute_retains_join_keys).unwrap_or(true),
  )
}

///|
/// Exact Host-side scratch facts from the selected managed query. Input count
/// is recorded so adding a multi-input implementation cannot silently inherit
/// the unary estimate. `retains_join_keys` concerns Host-side key arrays only;
/// native engine working memory remains covered by its separate reservation.
pub(all) struct ManagedStreamScratchFacts {
  input_count : Int
  retains_join_keys : Bool
}

///|
/// Managed scratch is bounded only when the selected query explicitly proves
/// that it keeps no Host-side join-key arrays. Query shape supplies these facts;
/// this function does not infer them from the managed profile name.
pub fn duckdb_managed_stream_scratch_capacity(
  limits : DuckDBComputeLimits,
  transport : @duckdb.TransportColumnLimits,
  facts : ManagedStreamScratchFacts,
) -> Int64? {
  if facts.input_count < 1 || facts.input_count > 2 {
    return None
  }
  stream_scratch_capacity(limits, transport, true, facts.retains_join_keys)
}

///|
fn stream_scratch_capacity(
  limits : DuckDBComputeLimits,
  transport : @duckdb.TransportColumnLimits,
  plan_known : Bool,
  retains_join_keys : Bool,
) -> Int64? {
  if plan_known &&
    (
      transport.max_bytes <= 0 ||
      transport.max_nodes <= 0 ||
      transport.max_rows <= 0 ||
      transport.max_columns <= 0
    ) {
    return None
  }
  guard duckdb_task_retention_capacity(limits) is Some(rows) &&
    duckdb_stream_retention_capacity(limits) is Some(retained) &&
    duckdb_task_scratch_capacity(limits, transport) is Some(scratch) else {
    return None
  }
  let full = scratch + (if rows > retained { rows - retained } else { 0L })
  if plan_known && !retains_join_keys {
    Some(Int64::min(full, bounded_stream_scratch_capacity(limits, transport)))
  } else {
    Some(full)
  }
}

///|
/// Called after validation of the capacity inputs above. Transport limits are
/// per-frame; value/demand/physical counters remain cumulative during execution.
fn bounded_stream_scratch_capacity(
  limits : DuckDBComputeLimits,
  transport : @duckdb.TransportColumnLimits,
) -> Int64 {
  let nodes = transport.max_nodes.to_int64() * 4L +
    transport.max_rows.to_int64() * 2L +
    transport.max_columns.to_int64() * 6L +
    limits.values.max_depth.to_int64() +
    limits.demand.max_depth.to_int64() +
    limits.retention.max_depth.to_int64() +
    limits.completion_entries.to_int64() * 2L +
    limits.metadata_work.to_int64() * 2L
  let texts = transport.max_bytes.to_int64() * 4L +
    transport.max_text_bytes.to_int64() * 4L +
    limits.completion_name_bytes.to_int64() * 2L
  nodes * 256L + texts * 8L
}
