///|
// Actual Journal transactions with observed routing. No installed physical
// scope, business capacity or authority is supplied by this diagnostic.
fn journal_start_operation_fixture(
  name : String,
) -> (@sqlite.Database, NativeClientRunJournal, @host.ClientRequestIdentity) raise {
  let database = epoch_test_database(name)
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    name + "-request",
    name + "-run",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  (database, journal, request)
}

///|
test "Work original routing retains first-start order and does not replace the physical claim" {
  let (database, journal, request) = journal_start_operation_fixture(
    "work-original-route",
  )
  let calls : Array[String] = []
  let operations = journal_test_operation_access(database, calls)
  let callbacks = Ref(0)
  let start = claim_native_client_retained_work_first_start_with_operations(
    journal,
    request,
    () => {
      callbacks.val += 1
      true
    },
    operations=Some(operations),
  ).unwrap()
  assert_eq(callbacks.val, 3)
  assert_eq(calls.filter(value => value == "begin"), ["begin", "begin", "begin"])
  assert_eq(calls.filter(value => value == "commit"), [
    "commit", "commit", "commit",
  ])
  let key = @host.client_request_scope_cid(request)
  assert_eq(
    calls.filter(value => value == "compare_exchange:client_runs:" + key),
    [
      "compare_exchange:client_runs:" + key,
      "compare_exchange:client_runs:" + key,
    ],
  )
  let original = database.read("client_runs", key).unwrap()
  calls.clear()
  assert_false(
    journal
    .claim_physical_start_with_operations(
      request,
      true,
      operations=Some(operations),
    )
    .unwrap(),
  )
  assert_false(calls.contains("compare_exchange:client_runs:" + key))
  let after = database.read("client_runs", key).unwrap()
  assert_eq(after.body, original.body)
  assert_eq(after.revision, original.revision)
  start.require_current(journal, request, () => true).unwrap()
  database.close_checked().unwrap()
}

///|
test "Work original routing rolls back an observed start CAS when its original operation refuses" {
  let (database, journal, request) = journal_start_operation_fixture(
    "work-original-rollback",
  )
  let key = @host.client_request_scope_cid(request)
  let before = database.read("client_runs", key).unwrap()
  let calls : Array[String] = []
  let observed = Ref(false)
  let access : NativeClientJournalOperationAccess = {
    ..journal_test_operation_access(database, calls),
    compare_exchange: (table, key, revision, body) => {
      database.compare_exchange(table, key, revision, body).unwrap() |> ignore
      observed.val = true
      Err(@sqlite.Busy)
    },
  }
  assert_true(
    journal.reserve_dispatch_with_operations(
      request,
      true,
      operations=Some(access),
    )
    is Err(Physical(@sqlite.Busy)),
  )
  assert_true(observed.val)
  assert_eq(calls[calls.length() - 1], "rollback")
  let after = database.read("client_runs", key).unwrap()
  assert_eq(after.body, before.body)
  assert_eq(after.revision, before.revision)
  assert_true(
    journal.lookup_with_reads(request, true, reads=Some(access.reads))
    is Ok(Retained(_)),
  )
  database.close_checked().unwrap()
}

///|
test "Work original routing retains a committed lost start reply as Unknown without a replacement claim" {
  let (database, journal, request) = journal_start_operation_fixture(
    "work-original-unknown",
  )
  journal.reserve_dispatch(request, true).unwrap() |> ignore
  let calls : Array[String] = []
  let ordinary = journal_test_read_access(database, calls)
  let reads : NativeClientJournalReadAccess = {
    ..ordinary,
    transaction: operation => {
      if operation is JournalCommit {
        database.commit().unwrap()
        calls.push("commit-lost")
        Err(@sqlite.Busy)
      } else {
        (ordinary.transaction)(operation)
      }
    },
  }
  let access = { ..journal_test_operation_access(database, calls), reads, }
  assert_true(
    journal.claim_physical_start_with_operations(
      request,
      true,
      operations=Some(access),
    )
    is Err(TransactionUnknown),
  )
  assert_true(journal.fenced)
  assert_true(database.transaction_fenced())
  let original = database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap()
  assert_true(read_run_record(original).unwrap().physical_start_claimed)
  calls.clear()
  assert_true(
    journal.claim_physical_start_with_operations(
      request,
      true,
      operations=Some(access),
    )
    is Err(Fenced),
  )
  assert_eq(calls, [])
  let after = database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap()
  assert_eq(after.body, original.body)
  assert_eq(after.revision, original.revision)
  database.close_checked().unwrap()
}
