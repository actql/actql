///|
test "scoped Root rejects a nonpositive diagnostic bound before acquisition" {
  let failure = match
    open_root_in_current_read_context_with_custody("/not-acquired", 0) {
    Err(original) => original
    Ok(_) => {
      fail("invalid diagnostic bound acquired a Root")
      return
    }
  }
  assert_true(failure.issue() is InvalidLimit)
  assert_true(failure.root is None)
  failure.retry_cleanup().unwrap()
  assert_true(failure.issue() is InvalidLimit)
}
