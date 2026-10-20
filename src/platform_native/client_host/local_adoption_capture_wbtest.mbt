///|
let adoption_capture_test_pending : Ref[NativeLocalAdoptionCapture?] = Ref(None)

///|
fn adoption_capture_test_input(
  name : String,
) -> NativeLocalExistingAdoptionInput {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  {
    parent_path: path,
    state_name: name + ".host",
    source_path: path,
    source_name: name + ".account.json",
    account_id: "operator",
    configuration_files: [],
    managed_root_path: None,
  }
}

///|
fn adoption_capture_test_retain(
  capture : NativeLocalAdoptionCapture,
) -> NativeLocalAdoptionCapture raise {
  assert_true(adoption_capture_test_pending.val is None)
  adoption_capture_test_pending.val = Some(capture)
  capture
}

///|
fn adoption_capture_test_close(
  capture : NativeLocalAdoptionCapture,
) -> Unit raise {
  let reply = capture.close()
  assert_true(reply.issue() is None)
  assert_eq(reply.operation_tag(), 3)
  assert_eq(reply.issue_family(), 0)
  assert_true(physical_equal(reply.original_capture(), capture))
  assert_true(capture.descriptor_cleanup_acknowledged())
  adoption_capture_test_pending.val = None
}

///|
fn adoption_capture_test_seed(
  name : String,
) -> NativeLocalAdoptionCapture raise {
  let host = local_journal_test_connection(name)
  host.close_owned_root_descriptors().unwrap()
  adoption_capture_test_retain(
    prepare_native_local_existing_adoption_capture(
      adoption_capture_test_input(name),
      epoch_test_crypto(),
    ).unwrap(),
  )
}

///|
test "adoption capture snapshots bounded input before I/O and abandonment never opens a Host" {
  let input = adoption_capture_test_input("adoption-capture-not-opened")
  let capture = adoption_capture_test_retain(
    prepare_native_local_existing_adoption_capture(input, epoch_test_crypto()).unwrap(),
  )
  input.configuration_files.push("caller-later.json")
  assert_eq(capture.input.configuration_files.length(), 0)
  assert_true(capture.original_session() is None)
  assert_true(capture.original_failure() is None)
  assert_true(capture.original_journal() is None)
  assert_true(
    capture.original.source_root is None && capture.original.lock is None,
  )
  assert_true(capture.check_current().issue() is Some(AdoptionNotOpened))
  assert_true(
    capture.capture_journal(local_journal_test_library(), 100.0, 8, 8388608L)
    is Err(AdoptionNotOpened),
  )
  adoption_capture_test_close(capture)
  assert_true(capture.open().issue() is Some(AdoptionCaptureClosed))
  let root = @filesystem.open_private_root(input.parent_path).unwrap()
  assert_true(root.inspect_directory(input.state_name).unwrap() is None)
  root.close().unwrap()
  let excessive = {
    ..input,
    configuration_files: Array::make(11, "unused.json"),
  }
  assert_true(
    prepare_native_local_existing_adoption_capture(
      excessive,
      epoch_test_crypto(),
    )
    is Err(ConfigurationLimit),
  )
}

///|
test "adoption capture keeps the same actual partial failure and lock until close acknowledges" {
  let name = "adoption-capture-missing"
  let (path, source, borrowed, _) = local_selected_source(name)
  let input = { ..adoption_capture_test_input(name), source_name: source, }
  assert_eq(input.parent_path, path)
  let capture = adoption_capture_test_retain(
    prepare_native_local_existing_adoption_capture(input, epoch_test_crypto()).unwrap(),
  )
  assert_true(capture.open().issue() is Some(AdoptionOriginal(CustodyLost)))
  let original = capture.original_failure().unwrap()
  assert_true(physical_equal(original, capture.original))
  assert_true(
    original.source_root is Some(_) &&
    original.parent is Some(_) &&
    original.lock is Some(_),
  )
  assert_true(capture.original_session() is None)
  assert_true(physical_equal(capture.open().original_capture(), capture))
  assert_true(physical_equal(capture.original_failure().unwrap(), original))
  adoption_open_require_locked(borrowed)
  adoption_capture_test_close(capture)
  assert_true(original.issue() is CustodyLost)
  assert_true(physical_equal(capture.original_failure().unwrap(), original))
  assert_true(borrowed.inspect_directory(input.state_name).unwrap() is None)
  borrowed.close().unwrap()
}

///|
test "adoption capture retains one legacy Session and observes its actual current original" {
  let capture = adoption_capture_test_seed("adoption-capture-current")
  assert_true(capture.open().issue() is None)
  let session = capture.original_session().unwrap()
  let intent = session.intent_cid()
  assert_true(session.existing_only)
  assert_false(session.initial_signing_eligible.val)
  assert_true(capture.open().issue() is None)
  assert_true(physical_equal(capture.original_session().unwrap(), session))
  assert_eq(capture.original_session().unwrap().intent_cid(), intent)
  assert_true(capture.check_current().issue() is None)
  session.closed = true
  assert_true(capture.check_current().issue() is Some(AdoptionOriginal(Closed)))
  adoption_capture_test_close(capture)
}

///|
test "adoption capture retains the inner journal before return and closes its database before roots" {
  let capture = adoption_capture_test_seed("adoption-capture-journal")
  assert_true(capture.open().issue() is None)
  let session = capture.original_session().unwrap()
  let journal = capture
    .capture_journal(local_journal_test_library(), 100.0, 8, 8388608L)
    .unwrap()
  assert_true(physical_equal(capture.original_journal().unwrap(), journal))
  assert_true(physical_equal(journal.original_session(), session))
  assert_true(
    capture.capture_journal(local_journal_test_library(), 200.0, 9, 16777216L)
    is Err(AdoptionJournalAlreadyCaptured),
  )
  assert_true(
    capture.check_current().issue() is Some(AdoptionJournal(JournalNotOpened)),
  )
  assert_eq(journal.open().issue_family(), 0)
  let host = journal.original_host().unwrap()
  assert_true(capture.check_current().issue() is None)
  local_test_fail_close(host.database, 1)
  assert_true(
    capture.close().issue() is Some(AdoptionJournal(JournalAdoption(_))),
  )
  assert_false(capture.descriptor_cleanup_acknowledged())
  assert_false(journal.descriptor_cleanup_acknowledged())
  session.root.private_ownership().unwrap() |> ignore
  adoption_open_require_locked(session.parent)
  adoption_capture_test_close(capture)
  assert_true(journal.descriptor_cleanup_acknowledged())
  assert_true(session.root.private_ownership() is Err(_))
  assert_true(capture.check_current().issue() is Some(AdoptionCaptureClosed))
}

///|
test "adoption capture preserves the original journal refusal through parent cleanup" {
  let capture = adoption_capture_test_seed("adoption-capture-journal-refused")
  assert_true(capture.open().issue() is None)
  let journal = capture
    .capture_journal(local_journal_test_library(), 0.0, 8, 8388608L)
    .unwrap()
  assert_eq(journal.open().issue_family(), 4)
  let failed = journal.original_failure().unwrap()
  assert_true(failed.issue() is InvalidInput)
  assert_true(
    capture.check_current().issue()
    is Some(AdoptionJournal(JournalAdoption(InvalidInput))),
  )
  adoption_capture_test_close(capture)
  assert_true(physical_equal(journal.original_failure().unwrap(), failed))
  assert_true(failed.issue() is InvalidInput)
}

///|
test "scoped adoption capture refuses missing actual read scope without a legacy fallback" {
  let capture = adoption_capture_test_retain(
    prepare_native_local_existing_adoption_capture_in_current_read_context(
      adoption_capture_test_input("adoption-capture-scoped"),
      epoch_test_crypto(),
      128,
    ).unwrap(),
  )
  assert_true(
    capture.open().issue()
    is Some(AdoptionOriginal(Filesystem(@filesystem.RootOpen(_)))),
  )
  assert_true(
    capture.original.source_root is None &&
    capture.original.parent is None &&
    capture.original.lock is None,
  )
  assert_true(capture.original_session() is None)
  adoption_capture_test_close(capture)
  assert_true(
    capture.original_failure().unwrap().issue()
    is Filesystem(@filesystem.RootOpen(_)),
  )
}

///|
// This is a synthetic missing return, with no in-flight physical call. Retain
// the known test-owned Root until explicit test cleanup; that close is never an
// acknowledgement of the interrupted operation represented by this capture.
test "unconfirmed adoption retains its partial carrier without retry or cleanup acknowledgement" {
  let capture = adoption_capture_test_retain(
    prepare_native_local_existing_adoption_capture(
      adoption_capture_test_input("adoption-capture-unconfirmed"),
      epoch_test_crypto(),
    ).unwrap(),
  )
  let root = @filesystem.open_private_root(capture.input.source_path).unwrap()
  capture.original.source_root = Some(root)
  capture.opening = AdoptionOpenUnconfirmed
  assert_true(capture.open().issue() is Some(AdoptionOpeningUnconfirmed))
  assert_true(
    capture.check_current().issue() is Some(AdoptionOpeningUnconfirmed),
  )
  assert_true(capture.close().issue() is Some(AdoptionOpeningUnconfirmed))
  assert_false(capture.descriptor_cleanup_acknowledged())
  assert_true(
    capture.original_session() is None && capture.original_failure() is None,
  )
  assert_true(physical_equal(capture.original.source_root.unwrap(), root))
  root.private_ownership().unwrap() |> ignore
  root.close().unwrap()
  assert_false(capture.descriptor_cleanup_acknowledged())
  adoption_capture_test_pending.val = None
}

///|
// Expected sticky Unknowns remain reachable through the test executable's
// lifetime; explicit fixture descriptor retirement below is not their ACK.
let adoption_capture_test_unknowns : Array[NativeLocalAdoptionCapture] = []

///|
test "adoption capture preserves a real Root close Unknown and never releases its original lock" {
  let name = "adoption-capture-root-unknown"
  let (_, source, borrowed, _) = local_selected_source(name)
  let input = { ..adoption_capture_test_input(name), source_name: source, }
  let capture = adoption_capture_test_retain(
    prepare_native_local_existing_adoption_capture(input, epoch_test_crypto()).unwrap(),
  )
  assert_true(capture.open().issue() is Some(AdoptionOriginal(CustodyLost)))
  let original = capture.original_failure().unwrap()
  let root = original.source_root.unwrap()
  adoption_open_fail_census_close(root, 1)
  assert_true(root.check_directory_members([]) is Err(@filesystem.Cleanup(_)))
  assert_true(
    capture.close().issue()
    is Some(AdoptionOriginal(Filesystem(@filesystem.Cleanup(_)))),
  )
  assert_false(capture.descriptor_cleanup_acknowledged())
  assert_true(physical_equal(original.source_root.unwrap(), root))
  assert_true(original.issue() is CustodyLost)
  adoption_open_require_locked(borrowed)
  assert_true(
    capture.close().issue()
    is Some(AdoptionOriginal(Filesystem(@filesystem.Cleanup(_)))),
  )
  assert_false(capture.descriptor_cleanup_acknowledged())
  assert_true(capture.open().issue() is Some(AdoptionCaptureClosed))
  // Isolated fixture cleanup only: it cannot turn the sticky Root outcome into
  // capture cleanup success or authorize a replacement open through the holder.
  original.lock.unwrap().close_checked().unwrap()
  assert_true(original.parent is None)
  borrowed.close().unwrap()
  assert_false(capture.descriptor_cleanup_acknowledged())
  adoption_capture_test_unknowns.push(capture)
  adoption_capture_test_pending.val = None
}
