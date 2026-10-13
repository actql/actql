///|
/// Portable missing-custody model only: no Root/Lock/SQLite physical execution.
test "missing constructor custody is not an empty cleanup acknowledgement" {
  let failure = store_open_failure(
    Filesystem(@filesystem.RootOpen("original refused open")),
    cleanup_gap=Some(RejectedRootCustodyUnavailable),
  )
  assert_true(failure.retry_cleanup() is Err(CleanupPending))
  assert_true(failure.retry_cleanup() is Err(CleanupPending))
  match failure.issue() {
    Filesystem(@filesystem.RootOpen(message)) =>
      assert_eq(message, "original refused open")
    _ => fail("cleanup changed the original Root refusal")
  }
}
