///|
/// Native missing-custody model only: no Root/Lock/SQLite physical execution.
test "missing constructor custody is not an empty cleanup acknowledgement" {
  let failure : NativePublicationStoreOpenFailure = {
    original_issue: Filesystem(@filesystem.RootOpen("original refused open")),
    operation_original: None,
    operation_database_alias: None,
    operation_return_pending: false,
    operation_children_closed: false,
    root: None,
    failed_root: None,
    lock: None,
    failed_lock: None,
    database: None,
    failed_database: None,
    cleanup_gap: Some(()),
  }
  assert_true(failure.retry_cleanup() is Err(CleanupPending))
  assert_true(failure.retry_cleanup() is Err(CleanupPending))
  match failure.issue() {
    Filesystem(@filesystem.RootOpen(message)) =>
      assert_eq(message, "original refused open")
    _ => fail("cleanup changed the original Root refusal")
  }
}
