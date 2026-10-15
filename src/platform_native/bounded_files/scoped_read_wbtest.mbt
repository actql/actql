///|
test "scoped bounded read refuses invalid bounds before any Root" {
  for ceiling in [0, -1] {
    let failure = match
      read_bounded_text_file_in_current_read_context_with_custody(
        "unopened", "unread", 1L, ceiling,
      ) {
      Err(original) => original
      Ok(_) => {
        fail("invalid scoped ceiling acquired input")
        return
      }
    }
    assert_true(failure.issue() is InvalidLimit)
    assert_true(failure.root is None)
    assert_true(failure.rejected_root is None)
    failure.retry_cleanup().unwrap()
  }
}
