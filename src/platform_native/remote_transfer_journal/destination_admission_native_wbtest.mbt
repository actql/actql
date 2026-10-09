///|
priv struct DestinationAdmissionFixture {
  journal : Journal
  library : @sqlite.Library
  path : String
  request : @transfer.RemoteTransferRequest
  receipt : @transfer.RemoteTransferDestinationReceipt
  key : String
}

///|
fn destination_admission_fixture(name : String) -> DestinationAdmissionFixture? {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return None
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return None
  }
  let library = @sqlite.load_library(path).unwrap()
  let path = root +
    "/destination-admission-" +
    name +
    "-" +
    @env.now().to_string() +
    ".sqlite3"
  let journal = open_journal(library, path, 262144L, 1, 4096, 5L).unwrap()
  let request = journal_request(@transfer.TransferStore)
  let (_, record) = journal.accept(request).unwrap()
  journal.commit_transition(@transfer.prepare_start(record).unwrap()).unwrap()
  journal
  .commit_transition(
    @transfer.prepare_source_settled(record, true, true).unwrap(),
  )
  .unwrap()
  journal
  .commit_transition(@transfer.prepare_destination_commit(record).unwrap())
  .unwrap()
  let receipt = @transfer.prepare_destination_receipt(
    request, "destination-material-a",
  ).unwrap()
  ignore(journal.commit_destination_receipt(receipt, request).unwrap())
  ignore(journal.reserve_destination_holding(request, 5L, 1L).unwrap())
  ignore(
    journal.acquire_destination_reader(request, receipt, "reader").unwrap(),
  )
  journal.validate_destination_reader(request, receipt, "reader").unwrap()
  Some({
    journal,
    library,
    path,
    request,
    receipt,
    key: @transfer.request_journal_identity(request).unwrap(),
  })
}

///|
test "destination admission separates mutable requests from retained scalar facts" {
  guard destination_admission_fixture("mutation") is Some(f) else { return }
  let journal = f.journal
  let initial = journal.destination_record_admission.unwrap()
  assert_eq(initial.revision, 3L)
  assert_eq(initial.attempt_state, 2)
  assert_eq(initial.integrity_state, 1)
  assert_eq(initial.destination_material_available, 1)
  let returned = journal.require(f.request).unwrap()
  let returned_manifest = @transfer.request_manifest(
    @transfer.record_request(returned),
  )
  let returned_chunk = returned_manifest.chunks[0]
  returned_manifest.chunks[0] = { ..returned_chunk, byte_length: 6L, }
  // The independently restored record must not share any memoized manifest.
  journal.validate_destination_reader(f.request, f.receipt, "reader").unwrap()
  assert_eq(journal.destination_record_admission.unwrap().body, initial.body)
  let caller_manifest = @transfer.request_manifest(f.request)
  let original_chunk = caller_manifest.chunks[0]
  caller_manifest.chunks[0] = { ..original_chunk, byte_length: 6L, }
  assert_true(
    journal.validate_destination_reader(f.request, f.receipt, "reader")
    is Err(Protocol(@transfer.InvalidTransfer)),
  )
  caller_manifest.chunks[0] = original_chunk
  journal.validate_destination_reader(f.request, f.receipt, "reader").unwrap()
  assert_true(journal.close())
  assert_true(journal.destination_record_admission is None)
  assert_true(
    journal.validate_destination_reader(f.request, f.receipt, "reader")
    is Err(Closed),
  )
  let reopened = open_journal(f.library, f.path, 262144L, 1, 4096, 5L).unwrap()
  assert_true(reopened.destination_record_admission is None)
  reopened.validate_destination_reader(f.request, f.receipt, "reader").unwrap()
  assert_true(reopened.close())
}

///|
test "destination admission fences unchanged bytes with a new SQL revision" {
  guard destination_admission_fixture("revision") is Some(f) else { return }
  let stored = f.journal.database.read("remote_transfer", f.key).unwrap()
  let other = f.library.open_database(f.path, 262144L).unwrap()
  assert_eq(
    other.compare_exchange("remote_transfer", f.key, 3L, stored.body).unwrap(),
    4L,
  )
  assert_true(
    f.journal.validate_destination_reader(f.request, f.receipt, "reader")
    is Err(StateCollision),
  )
  assert_true(f.journal.destination_record_admission is None)
  other.close()
  assert_true(f.journal.close())
}

///|
test "destination admission compares changed bytes at the same revision after rollback" {
  guard destination_admission_fixture("rollback-wire") is Some(f) else {
    return
  }
  let journal = f.journal
  let stored = journal.database.read("remote_transfer", f.key).unwrap()
  let original = @utf8.decode(stored.body) catch {
    _ => fail("invalid fixture UTF-8")
  }
  let next = original.replace(old="\"revision\":3", new="\"revision\":4")
  assert_true(next != original)
  journal.database.begin_immediate().unwrap()
  assert_eq(
    journal.database
    .compare_exchange("remote_transfer", f.key, 3L, journal_bytes(next))
    .unwrap(),
    4L,
  )
  assert_eq(
    journal.require_committed_destination(f.request, f.receipt).unwrap(),
    f.key,
  )
  assert_eq(journal.destination_record_admission.unwrap().revision, 4L)
  journal.database.rollback().unwrap()
  let other = f.library.open_database(f.path, 262144L).unwrap()
  assert_eq(
    other
    .compare_exchange("remote_transfer", f.key, 3L, journal_bytes(next + " "))
    .unwrap(),
    4L,
  )
  assert_true(
    journal.validate_destination_reader(f.request, f.receipt, "reader")
    is Err(Protocol(@transfer.InvalidTransfer)),
  )
  assert_true(journal.destination_record_admission is None)
  // A prior failure cannot hide a subsequent valid persisted record.
  let repaired = next.replace(old="\"revision\":4", new="\"revision\":5")
  assert_eq(
    other
    .compare_exchange("remote_transfer", f.key, 4L, journal_bytes(repaired))
    .unwrap(),
    5L,
  )
  journal.validate_destination_reader(f.request, f.receipt, "reader").unwrap()
  assert_eq(journal.destination_record_admission.unwrap().revision, 5L)
  other.close()
  assert_true(journal.close())
}

///|
test "destination admission observes noncommitted state at a previously admitted revision" {
  guard destination_admission_fixture("rollback-state") is Some(f) else {
    return
  }
  let journal = f.journal
  let stored = journal.database.read("remote_transfer", f.key).unwrap()
  let original = @utf8.decode(stored.body) catch {
    _ => fail("invalid fixture UTF-8")
  }
  let next = original.replace(old="\"revision\":3", new="\"revision\":4")
  journal.database.begin_immediate().unwrap()
  ignore(
    journal.database
    .compare_exchange("remote_transfer", f.key, 3L, journal_bytes(next))
    .unwrap(),
  )
  assert_eq(
    journal.require_committed_destination(f.request, f.receipt).unwrap(),
    f.key,
  )
  journal.database.rollback().unwrap()
  // A canonical failed state has no destination material, despite the same
  // revision and otherwise unchanged independently persisted receipt/reader.
  let failed = next
    .replace(old="\"attempt_state\":2", new="\"attempt_state\":3")
    .replace(
      old="\"destination_material_available\":true",
      new="\"destination_material_available\":false",
    )
  assert_true(failed != next)
  let other = f.library.open_database(f.path, 262144L).unwrap()
  assert_eq(
    other
    .compare_exchange("remote_transfer", f.key, 3L, journal_bytes(failed))
    .unwrap(),
    4L,
  )
  assert_true(
    journal.validate_destination_reader(f.request, f.receipt, "reader")
    is Err(RecoveryRequired),
  )
  assert_true(journal.destination_record_admission is None)
  other.close()
  assert_true(journal.close())
}

///|
test "destination admission preserves receipt errors before changed record errors" {
  guard destination_admission_fixture("precedence") is Some(f) else { return }
  let other = f.library.open_database(f.path, 262144L).unwrap()
  ignore(other.compare_exchange("remote_transfer", f.key, 3L, b"{}").unwrap())
  let foreign = @transfer.prepare_destination_receipt(
    f.request,
    "foreign-material",
  ).unwrap()
  assert_true(
    f.journal.validate_destination_reader(f.request, foreign, "reader")
    is Err(StateCollision),
  )
  assert_true(f.journal.destination_record_admission is None)
  assert_true(
    f.journal.validate_destination_reader(f.request, f.receipt, "reader")
    is Err(Protocol(@transfer.InvalidTransfer)),
  )
  other.close()
  assert_true(f.journal.close())
}

///|
test "destination admission remains scoped to each Journal admission policy" {
  guard destination_admission_fixture("policy") is Some(f) else { return }
  for policy in [(0, 4096, 5L), (1, 1, 5L), (1, 4096, 4L)] {
    let strict = open_journal(
      f.library,
      f.path,
      262144L,
      policy.0,
      policy.1,
      policy.2,
    ).unwrap()
    assert_true(strict.destination_record_admission is None)
    assert_true(
      strict.validate_destination_reader(f.request, f.receipt, "reader")
      is Err(Protocol(@transfer.InvalidTransfer)),
    )
    assert_true(strict.destination_record_admission is None)
    assert_true(strict.close())
  }
  let small_body = open_journal(f.library, f.path, 1L, 1, 4096, 5L).unwrap()
  assert_true(
    small_body.validate_destination_reader(f.request, f.receipt, "reader")
    is Err(Physical(@sqlite.Physical("invalid stored journal record"))),
  )
  assert_true(small_body.close())
  f.journal.validate_destination_reader(f.request, f.receipt, "reader").unwrap()
  assert_true(f.journal.close())
}

///|
test "destination admission observes cleanup and independent reader retirement" {
  guard destination_admission_fixture("retirement") is Some(f) else { return }
  let second = open_journal(f.library, f.path, 262144L, 1, 4096, 5L).unwrap()
  let record = second.require(f.request).unwrap()
  second
  .commit_transition(
    @transfer.prepare_cleanup(record, true, true, true).unwrap(),
  )
  .unwrap()
  assert_eq(@transfer.record_revision(f.journal.require(f.request).unwrap()), 4)
  // Transfer cleanup does not retire the separately owned destination material.
  f.journal.validate_destination_reader(f.request, f.receipt, "reader").unwrap()
  assert_eq(f.journal.destination_record_admission.unwrap().revision, 4L)
  assert_true(
    second.release_destination_reader(f.request, f.receipt, "reader").unwrap(),
  )
  assert_true(
    f.journal.validate_destination_reader(f.request, f.receipt, "reader")
    is Err(RecoveryRequired),
  )
  assert_true(
    second.begin_destination_material_reclaim(f.request, f.receipt).unwrap(),
  )
  assert_true(
    f.journal.acquire_destination_reader(f.request, f.receipt, "new-reader")
    is Err(RecoveryRequired),
  )
  assert_true(
    second
    .finish_destination_material_reclaim(f.request, f.receipt, true)
    .unwrap(),
  )
  assert_true(f.journal.close())
  assert_true(second.close())
}
