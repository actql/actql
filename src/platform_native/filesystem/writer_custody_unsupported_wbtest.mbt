///|
test "Writer custody unsupported target rejects before physical acquisition" {
  assert_true(open_private_root("/no-writer-custody") is Err(UnsupportedTarget))
  let failure : NativeWriterOpenFailure = {
    original_issue: UnsupportedTarget,
    writer: None,
  }
  failure.retry_cleanup().unwrap()
  assert_true(failure.issue() is UnsupportedTarget)
}
