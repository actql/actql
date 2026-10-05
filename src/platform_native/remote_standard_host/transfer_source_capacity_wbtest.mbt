///|
test "Transfer capture capacity covers decoded retention without acquisition capacity" {
  let limits = retained_source_limits()
  let capacity = native_remote_standard_transfer_source_capacity(limits).unwrap()
  assert_true(capacity.retained_bytes > 0L)
  assert_true(capacity.execution_bytes > 0L)
  assert_true(capacity.retained_bytes + capacity.execution_bytes < 536870912L)
  let larger = native_remote_standard_transfer_source_capacity({
    ..limits,
    max_rows: limits.max_rows + 1,
  }).unwrap()
  assert_true(larger.retained_bytes > capacity.retained_bytes)
}

///|
test "Transfer capture capacity refuses invalid limits before reservation" {
  let limits = retained_source_limits()
  assert_true(
    native_remote_standard_transfer_source_capacity({
      ..limits,
      max_read_bytes: 0,
    })
    is None,
  )
  assert_true(
    native_remote_standard_transfer_source_capacity({
      ..limits,
      values: { ..limits.values, max_nodes: -1, },
    })
    is None,
  )
  assert_true(
    native_remote_standard_transfer_source_capacity({
      ..limits,
      wire: { ..limits.wire, max_bytes: -1, },
    })
    is None,
  )
}
