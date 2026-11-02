///|
test "Source reader retains original request constructor without changing its original inventory" {
  let limits = [4, 6, 3, 4, 2, 3, 2, 2, 5, 7, 8, 2, 9, 10, 11, 4]
  let request = @execution.execution_capacity(17L, 23L).unwrap()
  let combined = installed_json_source_reader_capacity_with_request(
    limits,
    2,
    3,
    Some(request),
  ).unwrap()
  // The independent retained reader vector plus the selected original 17B.
  // Keep this composition attached to the original reader's current Source
  // workspace instead of a second frozen execution/NFC aggregate.
  assert_eq(@execution.execution_capacity_retained_bytes(combined), 3505L)
  let reader = installed_json_source_reader_capacity(limits, 2, 3).unwrap()
  assert_eq(
    @execution.execution_capacity_execution_bytes(combined),
    @execution.execution_capacity_execution_bytes(reader) + 23L,
  )
  assert_true(
    installed_json_source_reader_capacity_with_request(limits, 2, 3, None)
    is None,
  )
  let maximum = @execution.execution_capacity(
    9223372036854775807L, 9223372036854775807L,
  ).unwrap()
  assert_true(
    installed_json_source_reader_capacity_with_request(
      limits,
      2,
      3,
      Some(maximum),
    )
    is None,
  )
  assert_true(
    installed_json_source_reader_capacity_with_request([], 2, 3, Some(request))
    is None,
  )
}
