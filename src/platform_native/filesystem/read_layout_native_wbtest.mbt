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

///|
test "compiled Native Writer layout does not acquire a physical child" {
  let writer = native_filesystem_write_layout().unwrap()
  let reader = native_filesystem_read_layout().unwrap()
  assert_true(writer.writer_payload_bytes > 0L)
  assert_eq(
    writer.external_object_overhead_bytes,
    reader.external_object_overhead_bytes,
  )
  assert_eq(native_filesystem_write_layout(), Some(writer))
  assert_eq(write_layout_field_ffi(-1), -1L)
  assert_eq(write_layout_field_ffi(2), -1L)
}
