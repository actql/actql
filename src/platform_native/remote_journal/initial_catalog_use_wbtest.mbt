///|
test "initial Catalog envelopes require separate positive workspace and retained record capacity" {
  assert_true(
    initial_catalog_use_envelope_valid({
      record_bytes: 7L,
      retained_bytes: 9L,
      workspace_bytes: 5L,
    }),
  )
  assert_false(
    initial_catalog_use_envelope_valid({
      record_bytes: 7L,
      retained_bytes: 6L,
      workspace_bytes: 5L,
    }),
  )
  assert_false(
    initial_catalog_use_envelope_valid({
      record_bytes: 7L,
      retained_bytes: 9L,
      workspace_bytes: 0L,
    }),
  )
  assert_false(
    initial_catalog_use_envelope_valid({
      record_bytes: 0L,
      retained_bytes: 9L,
      workspace_bytes: 5L,
    }),
  )
}
