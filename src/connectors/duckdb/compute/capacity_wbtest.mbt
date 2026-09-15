///|
fn capacity_limits() -> DuckDBComputeLimits {
  {
    values: { max_work: 100, max_bytes: 100, max_nodes: 100, max_depth: 10, },
    demand: { max_work: 100, max_bytes: 100, max_nodes: 100, max_depth: 10, },
    physical: {
      max_rows: 10,
      max_cells: 10,
      max_nodes: 10,
      max_text_bytes: 100,
    },
    retention: {
      max_nodes: 100,
      max_text_bytes: 100,
      max_depth: 10,
      max_work: 1000,
    },
    metadata_work: 100,
    completion_entries: 100,
    completion_name_bytes: 1000,
  }
}

///|
test "connector container allowances preserve retained and working capacity independently" {
  let limits = capacity_limits()
  let transport : @duckdb.TransportColumnLimits = {
    max_bytes: 100000,
    max_nodes: 10000,
    max_columns: 10,
    max_rows: 100,
    max_text_bytes: 100000,
  }
  // Retained: (100 + 10 + 100) * 256 + (100 + 1000) * 8.
  assert_eq(duckdb_task_retention_capacity(limits), Some(62560L))
  // Working: 10470 nodes/entries + 201300 serialized/text bytes.
  assert_eq(duckdb_task_scratch_capacity(limits, transport), Some(4290720L))
  assert_eq(
    duckdb_task_retention_capacity({ ..limits, completion_entries: -1, }),
    None,
  )
  assert_eq(
    duckdb_task_scratch_capacity(limits, { ..transport, max_bytes: -1, }),
    None,
  )
  // Transport capacity is transient, never added to output retention.
  assert_eq(
    duckdb_task_scratch_capacity(limits, { ..transport, max_bytes: 100001, }),
    Some(4290728L),
  )
  assert_eq(duckdb_task_retention_capacity(limits), Some(62560L))
}
