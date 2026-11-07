///|
test "compiled Native layout facts are stable without opening a physical owner" {
  let first = native_filesystem_read_layout().unwrap()
  assert_true(first.root_payload_bytes > 0L)
  assert_true(first.reader_payload_bytes > 0L)
  assert_true(first.observation_payload_bytes > 0L)
  assert_true(first.acquisition_payload_bytes > 0L)
  assert_true(first.external_object_overhead_bytes > 0L)
  assert_eq(native_filesystem_read_layout(), Some(first))
}
