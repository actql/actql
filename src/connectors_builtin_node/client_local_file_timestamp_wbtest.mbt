///|
test "Local file metadata retains exact epoch parts through the existing UTC Owner" {
  assert_eq(
    client_program_local_file_timestamp(0L, 0),
    Some("1970-01-01T00:00:00.000Z"),
  )
  assert_eq(
    client_program_local_file_timestamp(0L, 1),
    Some("1970-01-01T00:00:00.000000001Z"),
  )
  assert_eq(
    client_program_local_file_timestamp(-1L, 999999999),
    Some("1969-12-31T23:59:59.999999999Z"),
  )
  assert_eq(
    client_program_local_file_timestamp(1704067200L, 123456789),
    Some("2024-01-01T00:00:00.123456789Z"),
  )
  assert_eq(client_program_local_file_timestamp(0L, -1), None)
  assert_eq(client_program_local_file_timestamp(0L, 1000000000), None)
  assert_eq(client_program_local_file_timestamp(9223372036854775807L, 0), None)
}
