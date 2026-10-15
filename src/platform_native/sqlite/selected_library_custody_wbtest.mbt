///|
test "selected SQLite Library empty failure custody preserves the original issue" {
  let original = {
    original_issue: LibraryLoad("original failed acquisition"),
    library: None,
  }
  original.retry_cleanup().unwrap()
  original.retry_cleanup().unwrap()
  assert_true(original.issue() is LibraryLoad("original failed acquisition"))
  assert_true(original.library is None)
}
