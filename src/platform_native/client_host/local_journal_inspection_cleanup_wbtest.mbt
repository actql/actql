///|
test "Journal refusal retains the original inspection DB cleanup before releasing its adoption lock" {
  let session = journal_open_original("journal-inspection-cleanup")
  let borrowed = @filesystem.open_private_root(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap(),
  ).unwrap()
  let inspected : Result[Unit, @journal.NativeRemoteJournalIssue] = @journal.inspect_sqlite_source(
    local_journal_test_library(),
    session.state_path + "/client.sqlite3",
    131072L,
    8388608L,
    database => {
      let database = database.unwrap()
      // First close fails in the original inspector; second close fails in
      // the Journal's cleanup. Both operate on this exact real copied DB.
      local_test_fail_close(database, 2)
      Err(@journal.StateCollision)
    },
  )
  let issue = match inspected {
    Err(original) => original
    Ok(_) => abort("inspection close fault unexpectedly succeeded")
  }
  let inspection = match issue {
    @journal.InitializationCleanupPending(
      Some(@journal.StateCollision),
      _,
      original
    ) => original
    _ => abort("original inspection cleanup was not retained")
  }
  assert_true(inspection.pending())
  let failure = session.retain_journal_open_failure(
    Inspection(Inspection(issue, None)),
    None,
  )
  assert_true(
    failure.inspection_cleanup is Some(original) &&
    physical_equal(original, inspection),
  )
  assert_true(failure.retry_cleanup() is Err(InspectionCleanup(_)))
  assert_true(inspection.pending())
  assert_false(failure.inspection_cleaned)
  assert_true(failure.acquisition.lock is Some(_))
  assert_true(failure.acquisition.root is Some(_))
  adoption_open_require_locked(borrowed)
  failure.retry_cleanup().unwrap()
  assert_false(inspection.pending())
  assert_true(failure.inspection_cleaned)
  assert_true(failure.acquisition.lock is None)
  assert_true(failure.acquisition.root is None)
  assert_true(
    failure.issue()
    is Inspection(
      Inspection(
        @journal.InitializationCleanupPending(
          Some(@journal.StateCollision),
          _,
          original
        ),
        None
      )
    ) &&
    physical_equal(original, inspection),
  )
  failure.retry_cleanup().unwrap()
  let lock = borrowed.acquire_lock("local-adoption.lock").unwrap()
  assert_true(lock.close())
  borrowed.close().unwrap()
}
