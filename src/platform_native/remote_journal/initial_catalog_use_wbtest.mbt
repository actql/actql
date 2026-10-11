///|
test "initial Catalog envelopes require separate positive disk control and workspace capacity" {
  assert_true(
    initial_catalog_use_envelope_valid({
      record_bytes: 7L,
      control_bytes: 2L,
      workspace_bytes: 5L,
    }),
  )
  assert_false(
    initial_catalog_use_envelope_valid({
      record_bytes: 7L,
      control_bytes: 0L,
      workspace_bytes: 5L,
    }),
  )
  assert_false(
    initial_catalog_use_envelope_valid({
      record_bytes: 7L,
      control_bytes: 2L,
      workspace_bytes: 0L,
    }),
  )
  assert_false(
    initial_catalog_use_envelope_valid({
      record_bytes: 0L,
      control_bytes: 2L,
      workspace_bytes: 5L,
    }),
  )
  assert_false(
    initial_catalog_use_envelope_valid({
      record_bytes: 9223372036854775807L,
      control_bytes: 1L,
      workspace_bytes: 1L,
    }),
  )
}
