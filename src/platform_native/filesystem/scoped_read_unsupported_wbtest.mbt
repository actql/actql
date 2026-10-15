///|
test "portable target cannot acquire a scoped physical Root" {
  let failure = match
    open_root_in_current_read_context_with_custody("/not-acquired", 16) {
    Err(original) => original
    Ok(_) => {
      fail("unsupported target acquired a physical Root")
      return
    }
  }
  assert_true(failure.issue() is UnsupportedTarget)
  assert_true(failure.root is None)
  failure.retry_cleanup().unwrap()
  assert_true(failure.issue() is UnsupportedTarget)
}
