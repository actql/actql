///|
test "metadata policy preserves zero wire legacy and rejects negative independent units" {
  let limits : @local.LocalImportLimits = {
    max_rows: 100,
    values: { max_nodes: 0, max_text_bytes: 0, max_depth: 1, max_work: 1, },
    wire: {
      max_columns: 1,
      max_order_work: 1,
      max_bytes: 0,
      max_nodes: 0,
      max_depth: 1,
    },
    row: { max_bytes: 0, max_nodes: 0, max_depth: 1, max_text_bytes: 0, },
    max_batch_bytes: 0,
  }
  let legacy = local_managed_metadata_limits(limits, None).unwrap()
  assert_eq(legacy.name_bytes, 0)
  assert_eq(legacy.schema.max_nodes, 0)
  assert_eq(legacy.bridge_entries, 0)
  assert_eq(legacy.completion_entries, 0)
  assert_eq(legacy.result_workspace_entries, 100)
  assert_eq(legacy.retained_bytes, 0L)
  for
    bad in [
      { ..legacy, schema: { ..legacy.schema, max_nodes: -1, }, },
      { ..legacy, schema: { ..legacy.schema, max_fields: -1, }, },
      { ..legacy, schema: { ..legacy.schema, max_bytes: -1, }, },
      { ..legacy, schema: { ..legacy.schema, max_depth: -1, }, },
      { ..legacy, name_bytes: -1, },
      { ..legacy, bridge_entries: -1, },
      { ..legacy, completion_entries: -1, },
      { ..legacy, result_workspace_entries: -1, },
      { ..legacy, retained_bytes: -1L, },
      { ..legacy, result_rows_reserved: Some(-1), },
      { ..legacy, result_rows_reserved: Some(101), },
    ] {
    assert_true(local_managed_metadata_limits(limits, Some(bad)) is None)
  }
  let independent = {
    ..legacy,
    schema: { ..legacy.schema, max_nodes: 100000, },
    bridge_entries: 100000,
    completion_entries: 100000,
    result_workspace_entries: 201,
    retained_bytes: 4096L,
  }
  assert_eq(
    local_managed_metadata_limits(limits, Some(independent)).unwrap().retained_bytes,
    4096L,
  )
  assert_eq(limits.wire.max_nodes, 0)
}

///|
test "metadata retained conversion rejects negative and overflow before reservation" {
  assert_eq(local_retained_with_metadata(0L, 0L), Some(0L))
  assert_eq(local_retained_with_metadata(123L, 456L), Some(579L))
  assert_eq(
    local_retained_with_metadata(9223372036854775806L, 1L),
    Some(9223372036854775807L),
  )
  assert_eq(local_retained_with_metadata(9223372036854775806L, 2L), None)
  assert_eq(local_retained_with_metadata(-1L, 0L), None)
  assert_eq(local_retained_with_metadata(0L, -1L), None)
}
