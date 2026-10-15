///|
/// No early return/skip: this selection requires an unentered Native Domain.
test "without an original active read scope no Root or failure descriptor is acquired" {
  assert_false(current_read_available_ffi())
  let failure = match
    open_root_in_current_read_context_with_custody("/not-acquired", 16) {
    Err(original) => original
    Ok(_) => {
      fail("missing original scope acquired a Root")
      return
    }
  }
  assert_true(failure.issue() is RootOpen(_))
  assert_true(failure.root is None)
  failure.retry_cleanup().unwrap()
  failure.retry_cleanup().unwrap()
  assert_true(failure.root is None)
  assert_true(failure.issue() is RootOpen(_))
}
