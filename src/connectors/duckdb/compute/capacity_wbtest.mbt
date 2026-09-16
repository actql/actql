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
test "bounded stream working capacity tracks frames not cumulative value counters" {
  let limits = capacity_limits()
  let transport : @duckdb.TransportColumnLimits = {
    max_bytes: 1000,
    max_nodes: 100,
    max_columns: 10,
    max_rows: 10,
    max_text_bytes: 1000,
  }
  // 910 node/metadata slots and 10000 encoding/text bytes.
  let expected = 312960L
  assert_eq(bounded_stream_scratch_capacity(limits, transport), expected)
  let larger = {
    ..limits,
    values: { ..limits.values, max_nodes: 1000000, max_bytes: 1000000, },
    demand: { ..limits.demand, max_nodes: 1000000, max_bytes: 1000000, },
    retention: {
      ..limits.retention,
      max_nodes: 1000000,
      max_text_bytes: 1000000,
    },
    physical: {
      max_rows: 1000000,
      max_cells: 1000000,
      max_nodes: 1000000,
      max_text_bytes: 1000000,
    },
  }
  assert_eq(bounded_stream_scratch_capacity(larger, transport), expected)
  assert_eq(
    bounded_stream_scratch_capacity(larger, { ..transport, max_nodes: 101, }),
    expected + 1024L,
  )
  assert_eq(
    bounded_stream_scratch_capacity(larger, { ..transport, max_bytes: 1001, }),
    expected + 32L,
  )
  // No exact prepared plan: do not silently drop potential retained join keys.
  assert_true(
    duckdb_stream_scratch_capacity(larger, transport).unwrap() > expected,
  )
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
  assert_eq(duckdb_stream_retention_capacity(limits), Some(59200L))
  assert_eq(duckdb_stream_scratch_capacity(limits, transport), Some(4294080L))
  let larger = {
    ..limits,
    retention: { ..limits.retention, max_nodes: 1000000, },
    physical: { ..limits.physical, max_rows: 1000000, },
  }
  assert_eq(duckdb_stream_retention_capacity(larger), Some(59200L))
  assert_eq(
    duckdb_stream_retention_capacity(larger).unwrap() +
    duckdb_stream_scratch_capacity(larger, transport).unwrap(),
    duckdb_task_retention_capacity(larger).unwrap() +
    duckdb_task_scratch_capacity(larger, transport).unwrap(),
  )
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
