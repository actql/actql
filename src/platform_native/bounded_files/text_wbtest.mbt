///|
test "bounded text rejects an invalid limit before physical access" {
  assert_true(
    read_bounded_text_file("unopened", "unread", 0L) is Err(InvalidLimit),
  )
}
