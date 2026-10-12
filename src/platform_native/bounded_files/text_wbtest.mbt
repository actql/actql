///|
test "bounded text rejects an invalid limit before physical access" {
  assert_true(
    read_bounded_text_file("unopened", "unread", 0L) is Err(InvalidLimit),
  )
}

///|
test "bounded read custody preserves the original refusal without a Reader" {
  guard read_bounded_text_file_with_custody("unopened", "unread", 0L)
    is Err(failure) else {
    fail("invalid limit reached physical access")
  }
  assert_true(failure.issue() is InvalidLimit)
  failure.retry_cleanup().unwrap()
  failure.retry_cleanup().unwrap()
  assert_true(failure.issue() is InvalidLimit)
}
