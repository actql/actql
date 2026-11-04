///|
test "Source reader retains original request constructor without changing its original inventory" {
  // Original current-pair and bound-reader links add 136 retained bytes;
  // response growth retains its pre-allocation method (one reference, 8B).
  // The same selected request still contributes its independent 17 bytes.
  let limits = [4, 6, 3, 4, 2, 3, 2, 2, 5, 7, 8, 2, 9, 10, 11, 4]
  let request = @execution.execution_capacity(17L, 23L).unwrap()
  let combined = installed_json_source_reader_capacity_with_request(
    limits,
    2,
    3,
    Some(request),
  ).unwrap()
  // Reader: 57 headers, 243 references, 34 words, 247 UTF16 units and 10
  // wire bytes give 3632B under the existing shared representation tariff.
  // The selected original request adds its independent 17B.
  // Keep this composition attached to the original reader's current Source
  // workspace instead of a second frozen execution/NFC aggregate.
  assert_eq(@execution.execution_capacity_retained_bytes(combined), 3632L + 17L)
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
