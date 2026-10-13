///|
fn transfer_journal_custody_library() -> (@sqlite.Library, String) {
  // Required fixture configuration: missing inputs fail discovery/execution,
  // never return early or manufacture a fallback Library.
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
    diagnostic_ceiling=Some(256),
  ).unwrap()
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  (library, root)
}

///|
#borrow(database)
extern "C" fn transfer_journal_fail_close(database : @sqlite.Database, failures : Int) -> Unit = "actql_native_sqlite_test_fail_close"

///|
test "Transfer Journal validation refusal has no acquired SQLite child" {
  let (library, root) = transfer_journal_custody_library()
  let name = "transfer-refusal-" + @env.now().to_string() + ".sqlite3"
  let path = root + "/" + name
  assert_true(open_journal_with_custody(library, path, 262144L, -1, 4096, 5L)
    is Err(RefusedBeforeAcquisition(Protocol(@transfer.InvalidTransfer))))
  let directory = @filesystem.open_root(root).unwrap()
  assert_eq(directory.inspect_generation(name).unwrap(), None)
  directory.close().unwrap()
}

///|
test "failed Transfer Journal open returns the same original SQLite cleanup responsibility" {
  let (library, root) = transfer_journal_custody_library()
  // An existing directory is not a writable SQLite file. No fixture-only
  // success response or reinitialization is substituted for the failed open.
  let failure = match open_journal_with_custody(library, root, 262144L, 1, 4096, 5L) {
    Err(CleanupRequired(original)) => original
    Err(RefusedBeforeAcquisition(_)) => { fail("physical constructor failure lost custody"); return }
    Ok(_) => { fail("directory admitted as SQLite journal"); return }
  }
  assert_true(failure.issue() is Physical(@sqlite.DatabaseOpen(_)))
  assert_true(failure.database is Some(_))
  failure.retry_cleanup().unwrap()
  assert_true(failure.database is None)
  failure.retry_cleanup().unwrap()
  assert_true(failure.issue() is Physical(@sqlite.DatabaseOpen(_)))
}

///|
test "Transfer Journal close failure keeps cache and original holding until Database acknowledgement" {
  let fixture = match destination_admission_fixture("close-custody") {
    Some(original) => original
    None => { fail("selected cache custody case needs actual isolated SQLite"); return }
  }
  let journal = fixture.journal
  let original_cache = journal.destination_record_admission.unwrap()
  let original_usage = journal.database.capacity_usage("remote_transfer_destination").unwrap()
  assert_eq(original_usage.reserved_bytes, 5L)
  assert_eq(original_usage.reserved_objects, 1L)
  let allocation = journal.prepare_destination_allocation(
    fixture.request, "close-custody-allocation", 0, "original-staging", "original-final",
  ).unwrap()
  let original_allocation = journal.database.read(
    "remote_transfer_destination_allocation", allocation.key,
  ).unwrap()
  transfer_journal_fail_close(journal.database, 1)
  assert_false(journal.close())
  assert_false(journal.closed)
  assert_true(journal.retiring)
  assert_true(physical_equal(journal.destination_record_admission.unwrap(), original_cache))
  assert_true(journal.require(fixture.request) is Err(CleanupPending))
  assert_true(journal.release_destination_allocation_intent(allocation) is Err(CleanupPending))
  let retained_allocation = journal.database.read(
    "remote_transfer_destination_allocation", allocation.key,
  ).unwrap()
  assert_eq(retained_allocation.revision, original_allocation.revision)
  assert_eq(retained_allocation.body, original_allocation.body)
  journal.close_checked().unwrap()
  assert_true(journal.closed)
  assert_true(journal.destination_record_admission is None)
  assert_true(journal.release_destination_allocation_intent(allocation) is Err(Closed))
  journal.close_checked().unwrap()
  let restored = open_journal_with_custody(fixture.library, fixture.path, 262144L, 1, 4096, 5L).unwrap()
  let retained_usage = restored.database.capacity_usage("remote_transfer_destination").unwrap()
  assert_eq(retained_usage.reserved_bytes, 5L)
  assert_eq(retained_usage.reserved_objects, 1L)
  // Handle retirement is not a destination holding release or execution ACK.
  assert_eq(@transfer.record_revision(restored.require(fixture.request).unwrap()), 3)
  assert_true(restored.close())
}
