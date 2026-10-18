///|
fn journal_capture_fixture(
  name : String,
  ttl? : Double = 100.0,
) -> NativeLocalJournalCapture {
  prepare_native_local_journal_capture(
    journal_open_original(name),
    local_journal_test_library(),
    epoch_test_crypto(),
    ttl,
    8,
    8388608L,
  )
}

///|
test "captured journal preparation performs no open and abandonment closes only original descriptors" {
  let capture = journal_capture_fixture("capture-before-open")
  let session = capture.original_session()
  assert_true(capture.original_host() is None)
  assert_true(capture.original_failure() is None)
  assert_eq(capture.check_current().issue_family(), 1)
  session.check_original().unwrap()
  adoption_open_require_locked(session.parent)
  let borrowed = @filesystem.open_private_root(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap(),
  ).unwrap()
  assert_eq(capture.close().issue_family(), 0)
  assert_true(capture.descriptor_cleanup_acknowledged())
  assert_true(session.parent.private_ownership() is Err(_))
  borrowed.private_ownership().unwrap() |> ignore
  borrowed.close().unwrap()
  assert_eq(capture.open().issue_family(), 3)
  assert_true(capture.original_host() is None)
}

///|
test "captured journal keeps one original Host and checks actual current binding on every observation" {
  let capture = journal_capture_fixture("capture-current")
  assert_eq(capture.open().issue_family(), 0)
  let host = capture.original_host().unwrap()
  assert_true(physical_equal(capture.open().original_capture(), capture))
  assert_true(physical_equal(capture.original_host().unwrap(), host))
  assert_eq(capture.check_current().issue_family(), 0)
  host.session.closed = true
  assert_eq(capture.check_current().issue_family(), 4)
  assert_true(capture.check_current().issue() is Some(JournalAdoption(Closed)))
  assert_eq(capture.close().issue_family(), 0)
  assert_eq(capture.check_current().issue_family(), 3)
}

///|
test "captured journal retains the exact opening refusal after cleanup and cannot open again" {
  let capture = journal_capture_fixture("capture-refusal", ttl=0.0)
  assert_eq(capture.open().issue_family(), 4)
  let original = capture.original_failure().unwrap()
  assert_true(original.issue() is InvalidInput)
  assert_eq(capture.open().issue_family(), 4)
  assert_true(physical_equal(capture.original_failure().unwrap(), original))
  assert_eq(capture.close().issue_family(), 0)
  assert_eq(capture.original_issue_family(), 4)
  assert_true(physical_equal(capture.original_failure().unwrap(), original))
  assert_true(original.issue() is InvalidInput)
  assert_eq(capture.open().issue_family(), 3)
}

///|
test "captured failed open keeps primary cause and pending database until its original close ACK" {
  let capture = prepare_native_local_journal_capture(
    journal_open_lost_adoption("capture-db-pending"),
    local_journal_test_library(),
    epoch_test_crypto(),
    100.0,
    8,
    8388608L,
  )
  assert_eq(capture.open().issue_family(), 4)
  let original = capture.original_failure().unwrap()
  let database = original.database.unwrap()
  local_test_fail_close(database, 1)
  assert_eq(capture.close().issue_family(), 4)
  assert_false(capture.descriptor_cleanup_acknowledged())
  assert_true(physical_equal(original.database.unwrap(), database))
  assert_true(
    original.issue() is DatabasePending(retained, CustodyLost) &&
    physical_equal(retained, database),
  )
  adoption_open_require_locked(capture.original_session().parent)
  assert_eq(capture.open().issue_family(), 3)
  assert_eq(capture.close().issue_family(), 0)
  assert_true(original.database is None)
  assert_true(
    original.issue() is DatabasePending(retained, CustodyLost) &&
    physical_equal(retained, database),
  )
  let count = local_owned_roots_checked_close_count(database)
  assert_eq(capture.close().issue_family(), 0)
  assert_eq(local_owned_roots_checked_close_count(database), count)
}

///|
test "captured inner descriptor close does not acknowledge an escaped original Reader" {
  let capture = journal_capture_fixture("capture-reader-alias")
  assert_eq(capture.open().issue_family(), 0)
  let session = capture.original_session()
  let reader = session.source_root
    .open_reader(session.source_name, session.source_generation)
    .unwrap()
  assert_eq(capture.close().issue_family(), 0)
  assert_true(capture.descriptor_cleanup_acknowledged())
  assert_eq(reader.next(1).unwrap().bytes, b"{")
  reader.close().unwrap()
}

///|
// This synthetic interruption marks no completed open and has no real pending
// SQL call. Its test-owned Session cleanup below is NOT an open-outcome ACK.
test "captured missing open outcome never retries or invents a cleanup acknowledgement" {
  let capture = journal_capture_fixture("capture-unconfirmed")
  capture.opening = JournalOpenUnconfirmed
  assert_eq(capture.open().issue_family(), 2)
  assert_eq(capture.check_current().issue_family(), 2)
  assert_eq(capture.close().issue_family(), 2)
  assert_false(capture.descriptor_cleanup_acknowledged())
  assert_eq(capture.original_issue_family(), 2)
  assert_true(capture.original_host() is None)
  assert_true(capture.original_failure() is None)
  let session = capture.original_session()
  adoption_open_require_locked(session.parent)
  assert_true(session.close())
  close_local_session_owned_root_descriptors(session).unwrap()
  assert_false(capture.descriptor_cleanup_acknowledged())
}
