///|
test "Journal refusal keeps its original inspection DB and lock until cleanup acknowledges" {
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
      // Original inspector close, then original Journal cleanup close, fail
      // on this same real copied database. No source DB is opened for writing.
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
  )
  let cleanup = failure.retry_cleanup()
  assert_true(inspection.pending())
  // Observe the actual exclusive lock, not a cached cleanup flag. A failed
  // contender retains and closes only its own original acquisition carrier.
  let blocked = match
    borrowed.acquire_lock_with_custody("local-adoption.lock") {
    Err(original) => {
      original.retry_cleanup().unwrap()
      true
    }
    Ok(lock) => {
      lock.close_checked().unwrap()
      false
    }
  }
  if !blocked {
    fail(
      "Journal released its adoption lock with original inspection cleanup pending",
    )
  }
  assert_true(cleanup is Err(_))
  session.parent.private_ownership().unwrap() |> ignore
  failure.retry_cleanup().unwrap()
  assert_false(inspection.pending())
  assert_true(session.parent.private_ownership() is Err(_))
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
  let lock = borrowed.acquire_lock_with_custody("local-adoption.lock").unwrap()
  lock.close_checked().unwrap()
  borrowed.close().unwrap()
}
