///|
fn required_site_close_custody_fixture() -> (@sqlite.Library, String) {
  // Required physical configuration never skips a selected case. Original
  // integration DBs are not used; the caller supplies owned isolated scratch.
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
    diagnostic_ceiling=Some(256),
  ).unwrap()
  (library, @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap())
}

///|
test "Site Journal open refusal and actual failed-open custody remain separate" {
  let (library, root) = required_site_close_custody_fixture()
  let control = test_control(test_site())
  let absent = root + "/site-journal-invalid-limit.sqlite3"
  assert_true(
    open_journal_with_custody(library, absent, -1L, control)
    is Err(RefusedBeforeAcquisition(Physical(@sqlite.InvalidLimit))),
  )
  let original = match
    open_journal_with_custody(library, root, 262144L, control) {
    Err(CleanupRequired(failure)) => failure
    _ => {
      fail("failed physical Journal constructor lost SQLite custody")
      return
    }
  }
  assert_true(original.failed_open is Some(_))
  assert_true(original.initialized_database is None)
  assert_true(original.issue() is Physical(@sqlite.DatabaseOpen(_)))
  original.retry_cleanup().unwrap()
  assert_true(original.failed_open is None)
  original.retry_cleanup().unwrap()
  assert_true(original.issue() is Physical(@sqlite.DatabaseOpen(_)))
  let directory = @filesystem.open_root(root).unwrap()
  assert_eq(
    directory.inspect_generation("site-journal-invalid-limit.sqlite3").unwrap(),
    None,
  )
  directory.close().unwrap()
}

///|
test "Site Journal binding rejection retains the exact initialized Database through failed cleanup" {
  let (library, root) = required_site_close_custody_fixture()
  let path = root + "/site-journal-binding-custody.sqlite3"
  let control = test_control(test_site())
  let initial = open_journal_with_custody(library, path, 262144L, control).unwrap()
  initial.close_checked().unwrap()
  let foreign_site = @site.create_site(
    "native-site",
    5,
    test_cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    4,
    4,
    1048576L,
    1048576L,
  ).unwrap()
  let original = match
    open_journal_with_custody(
      library,
      path,
      262144L,
      test_control(foreign_site),
    ) {
    Err(CleanupRequired(failure)) => failure
    _ => {
      fail("foreign durable binding lost initialized Database")
      return
    }
  }
  let database = original.initialized_database.unwrap()
  assert_true(original.issue() is StateCollision)
  test_fail_inspection_close(database, 1)
  assert_true(original.retry_cleanup() is Err(Physical(_)))
  assert_true(
    original.initialized_database is Some(retained) &&
    physical_equal(retained, database),
  )
  assert_true(original.issue() is StateCollision)
  original.retry_cleanup().unwrap()
  assert_true(original.initialized_database is None)
  original.retry_cleanup().unwrap()
  assert_true(original.issue() is StateCollision)
  // No replacement binding or dispatch is written by handle cleanup.
  let reopened = open_journal_with_custody(library, path, 262144L, control).unwrap()
  assert_true(reopened.recover_after("").unwrap() is None)
  reopened.close_checked().unwrap()
}

///|
test "Site Journal failed close retains original records and reservations and refuses new I/O" {
  let (library, root) = required_site_close_custody_fixture()
  let path = root + "/site-journal-close-custody.sqlite3"
  let control = test_control(test_site())
  let original = open_journal_with_custody(library, path, 262144L, control).unwrap()
  let request = test_request("site-close-custody")
  let (kind, record) = original.accept(request).unwrap()
  assert_eq(kind, @remote.NewDispatch)
  assert_eq(@remote.dispatch_record_revision(record), 0)
  assert_true(
    original.database
    .reserve_capacity("close-custody", "original", 7L, 1L, 7L, 1L)
    .unwrap(),
  )
  test_fail_inspection_close(original.database, 1)
  assert_false(original.close())
  assert_false(original.closed)
  assert_true(original.retiring)
  assert_true(original.require(request) is Err(CleanupPending))
  assert_true(original.request_cancellation(request) is Err(CleanupPending))
  assert_true(original.has_effect_checkpoint_reports() is Err(CleanupPending))
  assert_eq(test_checked_close_count(original.database), 1)
  original.close_checked().unwrap()
  assert_true(original.closed)
  assert_eq(test_checked_close_count(original.database), 2)
  assert_true(original.has_effect_checkpoint_reports() is Err(Closed))
  original.close_checked().unwrap()
  assert_false(original.close())
  assert_eq(test_checked_close_count(original.database), 2)
  let restored = open_journal_with_custody(library, path, 262144L, control).unwrap()
  let recovered = restored.require(request).unwrap()
  assert_eq(@remote.dispatch_record_revision(recovered), 0)
  assert_eq(@remote.dispatch_record_state_codes(recovered)[0], 0)
  let holding = restored.database.capacity_usage("close-custody").unwrap()
  assert_eq(holding.reserved_bytes, 7L)
  assert_eq(holding.reserved_objects, 1L)
  assert_false(restored.cancellation_requested(request).unwrap())
  restored.close_checked().unwrap()
}

///|
test "Coordinator Journal retries original checked close without rewriting the durable attempt" {
  let (library, root) = required_site_close_custody_fixture()
  let path = root + "/coordinator-journal-close-custody.sqlite3"
  let control = @remote.create_coordinator_dispatch_journal(
    "native-coordinator",
  ).unwrap()
  let original = open_coordinator_journal(library, path, 262144L, control).unwrap()
  let request = test_request("coordinator-close-custody")
  let (kind, record) = original.accept(request).unwrap()
  assert_eq(kind, @remote.NewDispatch)
  assert_eq(@remote.coordinator_dispatch_record_revision(record), 0)
  test_fail_inspection_close(original.database, 1)
  assert_false(original.close())
  assert_false(original.closed)
  assert_true(original.retiring)
  assert_true(original.require(request) is Err(CleanupPending))
  assert_true(original.accept(request) is Err(CleanupPending))
  original.close_checked().unwrap()
  assert_true(original.closed)
  original.close_checked().unwrap()
  assert_false(original.close())
  assert_eq(test_checked_close_count(original.database), 2)
  let restored = open_coordinator_journal(library, path, 262144L, control).unwrap()
  assert_eq(
    @remote.coordinator_dispatch_record_revision(
      restored.require(request).unwrap(),
    ),
    0,
  )
  restored.close_checked().unwrap()
}
