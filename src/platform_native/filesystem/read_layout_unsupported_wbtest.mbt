///|
test "unsupported backend cannot issue Native filesystem layout facts" {
  assert_true(native_filesystem_read_layout() is None)
}
