///|
test "publication limit ABI round trips twenty two distinct sentinels" {
  let limits = client_program_effect_input_export_limits(
    101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116,
    117, 118, 119, 120, 121, 122,
  ).unwrap()
  assert_eq(limits.max_result_workspace_entries, 104)
  assert_eq(limits.values.max_text_bytes, 107)
  assert_eq(limits.payload_wire.max_columns, 113)
  assert_eq(limits.logical_wire.max_depth, 117)
  assert_eq(limits.schema.max_bytes, 119)
  let projected = client_publication_limit_values(limits)
  assert_eq(projected.length(), 22)
  for index in 0..<22 {
    assert_eq(projected[index], 101 + index)
  }
}
