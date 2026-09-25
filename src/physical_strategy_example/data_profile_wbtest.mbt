///|
test "explicit data profile preserves distinct source and intermediate row bounds" {
  let data : DataProfile = {
    source_rows: 1000,
    task_rows: 2000,
    columns: 64,
    value_bytes: 2048,
    wire_bytes: 1000000,
    value_nodes: 200000,
    text_bytes: 1000000,
    work: 10000000,
    entries: 200000,
    batch_bytes: 100000,
  }
  assert_true(@manifest.validate_data_profile(data))
  let acquisition = acquisition_limits(data=Some(data))
  let dispatch = dispatch_limits(data=Some(data))
  assert_eq(acquisition.physical.max_rows, 3000)
  assert_eq(acquisition.physical.max_cells, 192000)
  assert_eq(acquisition.output_rows, 1000)
  assert_eq(acquisition.output_entries, 64)
  assert_eq(acquisition.transport.max_rows, 512)
  assert_eq(acquisition.transport.max_bytes, data.batch_bytes)
  assert_eq(acquisition.transport.max_nodes, 32833)
  assert_eq(acquisition.measurement.max_bytes, 2000000)
  assert_eq(acquisition.completion.receipts.max_bytes, 2000000)
  assert_eq(acquisition.completion.max_retained_wire_bytes, 2000000)
  assert_eq(acquisition.completion.records.max_fields, 128)
  assert_eq(dispatch.capacity.max_rows, 2000)
  assert_eq(dispatch.join_validation.max_rows, 2000)
  assert_eq(dispatch.native.physical.max_cells, 128000)
  assert_eq(dispatch.local_execution.rows.max_rows, 2000)
  assert_eq(dispatch.guards.max_work, data.work)
  assert_eq(dispatch.guards.max_bytes, 3000000)
  assert_eq(dispatch.native_query.max_entries, data.entries)
  assert_eq(profile_compute_transfer_capacity(data), 36800192L)
  assert_eq(profile_resident_import_scratch(data), 47296576L)
  assert_true(
    profile_managed_retention_capacity(data, 1, true).unwrap() <
    profile_managed_retention_capacity(data, 64, true).unwrap(),
  )
  assert_true(profile_managed_retention_capacity(data, 65, true) is None)
  assert_true(
    profile_resident_import_scratch({ ..data, batch_bytes: 200000, }) >
    profile_resident_import_scratch(data),
  )
  assert_true(
    profile_resident_import_scratch({ ..data, columns: 65, }) >
    profile_resident_import_scratch(data),
  )
  assert_eq(dispatch.native.demand.max_work, data.work)
  assert_eq(dispatch.native.retention.max_nodes, data.value_nodes)
  assert_eq(dispatch.native.completion_entries, 64)
  let more_values = { ..data, entries: 1000000, value_nodes: 1000000, }
  assert_eq(
    acquisition_limits(data=Some(more_values)).output_entries,
    acquisition.output_entries,
  )
  assert_eq(
    dispatch_limits(data=Some(more_values)).native.completion_entries,
    dispatch.native.completion_entries,
  )
  assert_eq(
    @duckdb_compute.duckdb_stream_retention_capacity(
      dispatch_limits(data=Some(more_values)).native,
    ),
    @duckdb_compute.duckdb_stream_retention_capacity(dispatch.native),
  )
  assert_eq(acquisition.metadata_work, 100000)
  assert_eq(dispatch.native.metadata_work, 100000)
  let larger = { ..data, source_rows: 10000, task_rows: 20000, }
  assert_eq(
    acquisition_limits(data=Some(larger)).metadata_work,
    acquisition.metadata_work,
  )
  assert_eq(
    dispatch_limits(data=Some(larger)).native.metadata_work,
    dispatch.native.metadata_work,
  )
  assert_eq(
    dispatch.local_execution.rows.input_values.max_nodes,
    data.value_nodes,
  )
  assert_eq(acquisition_limits().physical.max_rows, 100)
  assert_eq(dispatch_limits().capacity.max_rows, 100)
  assert_eq(dispatch_limits().native_query.max_entries, 100)
  for
    invalid in [
      { ..data, source_rows: 0, },
      { ..data, task_rows: -1, },
      { ..data, columns: 257, },
      { ..data, source_rows: 2147483647, },
      { ..data, task_rows: 2147483647, },
      { ..data, work: 0, },
      { ..data, batch_bytes: 1000001, },
      { ..data, wire_bytes: 715827883, },
    ] {
    assert_false(@manifest.validate_data_profile(invalid))
  }
}
