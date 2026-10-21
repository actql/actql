///|
test "ordinary Run open and target lookup do not inspect unrelated history" {
  let database = epoch_test_database("journal-target-reads")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "target-request", "target-run",
  )
  let expected = journal
    .bind_run(request, prepared, compiled, definition, true)
    .unwrap()
  // These are unrelated records, not the selected original's custody. An
  // explicit integrity inventory can still diagnose them independently.
  database.insert("client_runs", "unrelated", b"{}").unwrap() |> ignore
  database
  .insert("client_effect_custody", "unrelated", b"invalid historic effect")
  .unwrap()
  |> ignore
  let calls : Array[String] = []
  let reads = journal_test_read_access(database, calls)
  let reopened = open_native_client_run_journal_with_reads(
    database,
    8,
    reads=Some(reads),
  ).unwrap()
  assert_eq(calls, [
    "fenced", "run-definition-schema", "read:client_run_custody:issued",
  ])
  calls.clear()
  let actual = reopened
    .lookup_with_reads(request, true, reads=Some(reads))
    .unwrap()
  guard actual is Retained(actual) else { fail("missing selected Run") }
  assert_eq(actual.revision, expected.revision)
  assert_eq(calls, [
    "fenced",
    "begin",
    "read:client_run_custody:issued",
    "read:client_runs:" + @host.client_request_scope_cid(request),
    "read:client_effect_custody:" + @host.client_request_scope_cid(request),
    "commit",
  ])
  assert_true(run_journal_custody(database, 8) is Err(CustodyLost))
  // Selected corruption still refuses, and the transaction rolls back.
  let key = @host.client_request_scope_cid(request)
  let row = database.read("client_runs", key).unwrap()
  database.compare_exchange("client_runs", key, row.revision, b"{}").unwrap()
  |> ignore
  calls.clear()
  assert_true(
    reopened.lookup_with_reads(request, true, reads=Some(reads))
    is Err(CustodyLost),
  )
  assert_eq(calls[calls.length() - 1], "rollback")
  database.close_checked().unwrap()
}

///|
test "ordinary target lookup preserves selected Effect witness and issuance rollback refusal" {
  let database = epoch_test_database("journal-target-witness")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "witness-request", "witness-run",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  database
  .insert(
    "client_effect_custody",
    @host.client_request_scope_cid(request),
    b"foreign witness",
  )
  .unwrap()
  |> ignore
  assert_true(journal.lookup(request, true) is Err(CustodyLost))
  let issued = database.read("client_run_custody", "issued").unwrap()
  database
  .compare_exchange("client_run_custody", "issued", issued.revision, b"0")
  .unwrap()
  |> ignore
  assert_true(open_native_client_run_journal(database, 8) is Err(CustodyLost))
  database.close_checked().unwrap()
}

///|
test "same Journal snapshot reuses its admitted Run and invalidates on mutation and frame end" {
  let database = epoch_test_database("journal-snapshot-admission")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "snapshot-request", "snapshot-run",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let (first, again) = journal
    .transaction(() => {
      let first = journal.retained(request).unwrap().unwrap()
      let again = journal.retained(request).unwrap().unwrap()
      Ok((first, again))
    })
    .unwrap()
  assert_true(physical_equal(first, again))
  assert_true(journal.admitted_record is None)
  let later = journal.lookup(request, true).unwrap()
  guard later is Retained(later) else { fail("missing original") }
  assert_false(physical_equal(first, later))
  let failed : Result[Unit, NativeClientRunJournalIssue] = journal.transaction(() => {
    let original = journal.retained(request).unwrap().unwrap()
    database
    .compare_exchange(
      "client_runs",
      @host.client_request_scope_cid(request),
      original.revision,
      b"{}",
    )
    .unwrap()
    |> ignore
    match journal.retained(request) {
      Err(issue) => Err(issue)
      Ok(_) => Ok(())
    }
  })
  assert_true(failed is Err(CustodyLost))
  assert_true(journal.admitted_record is None)
  guard journal.lookup(request, true).unwrap() is Retained(restored) else {
    fail("rollback lost original")
  }
  assert_eq(restored.revision, first.revision)
  database.close_checked().unwrap()
}

///|
test "fresh Run binding uses its local issuance and physical uniqueness without inventory" {
  let database = epoch_test_database("journal-local-append")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  // Valid SQLite JSON is deliberately not a valid typed Run original. NULL in
  // the index cannot substitute for selected row admission or a history audit.
  database.insert("client_runs", "unrelated", b"{}").unwrap() |> ignore
  database
  .insert("client_effect_custody", "unrelated", b"unrelated effect")
  .unwrap()
  |> ignore
  let (request, _, _, definition) = journal_test_run(
    "local-append", "local-append-run",
  )
  let calls : Array[String] = []
  let operations = journal_test_operation_access(database, calls)
  journal
  .transaction_with_reads(
    () => {
      journal.bind_run_locked(request, definition, operations=Some(operations))
    },
    reads=Some(operations.reads),
  )
  .unwrap()
  |> ignore
  assert_false(calls.any(value => value.has_prefix("scan:")))
  assert_eq(
    calls.filter(value => value.has_prefix("insert:client_runs:")).length(),
    1,
  )
  assert_eq(database.read("client_run_custody", "issued").unwrap().body, b"1")
  assert_true(run_journal_custody(database, 8) is Err(CustodyLost))
  database.close_checked().unwrap()
}

///|
test "actual duplicate definition rejection rolls back the Run issuance CAS" {
  let database = epoch_test_database("journal-duplicate-rollback")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "duplicate-first", "duplicate-run",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let (next, _, _, _) = journal_test_run("duplicate-next", "different-run")
  let calls : Array[String] = []
  let operations = journal_test_operation_access(database, calls)
  assert_true(
    journal.transaction_with_reads(
      () => {
        journal.bind_run_locked(next, definition, operations=Some(operations))
      },
      reads=Some(operations.reads),
    )
    is Err(Physical(@sqlite.Collision)),
  )
  assert_true(calls.contains("compare_exchange:client_run_custody:issued"))
  assert_true(
    calls.contains("insert:client_runs:" + @host.client_request_scope_cid(next)),
  )
  assert_eq(calls[calls.length() - 1], "rollback")
  assert_eq(database.read("client_run_custody", "issued").unwrap().body, b"1")
  assert_true(
    database.read("client_runs", @host.client_request_scope_cid(next))
    is Err(@sqlite.NotFound),
  )
  guard journal.lookup(request, true).unwrap() is Retained(original) else {
    fail("original Run lost")
  }
  assert_eq(original.revision, 0L)
  database.close_checked().unwrap()
}

///|
test "selected definition replacement uses the same Run CAS and actual unique constraint" {
  let database = epoch_test_database("journal-definition-replacement")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "definition-first", "first-definition",
  )
  let original = journal
    .bind_run(request, prepared, compiled, definition, true)
    .unwrap()
  let (other, prepared, compiled, other_definition) = journal_test_run(
    "definition-other", "other-definition",
  )
  journal.bind_run(other, prepared, compiled, other_definition, true).unwrap()
  |> ignore
  let calls : Array[String] = []
  let operations = journal_test_operation_access(database, calls)
  assert_true(
    journal.transaction_with_reads(
      () => {
        journal.save_with_operations(
          { ..original, definition: other_definition, },
          operations=Some(operations),
        )
      },
      reads=Some(operations.reads),
    )
    is Err(Physical(@sqlite.Collision)),
  )
  assert_eq(calls[calls.length() - 1], "rollback")
  guard journal.lookup(request, true).unwrap() is Retained(restored) else {
    fail("original Run lost")
  }
  assert_eq(restored.revision, original.revision)
  assert_eq(
    @publication.publication_contract_identity(restored.definition),
    @publication.publication_contract_identity(definition),
  )
  let (_, _, _, replacement) = journal_test_run(
    "definition-first", "new-definition",
  )
  calls.clear()
  let next = journal
    .transaction_with_reads(
      () => {
        journal.save_with_operations(
          { ..restored, definition: replacement, },
          operations=Some(operations),
        )
      },
      reads=Some(operations.reads),
    )
    .unwrap()
  assert_eq(next.revision, original.revision + 1L)
  assert_false(calls.any(value => value.has_prefix("scan:")))
  database.close_checked().unwrap()
}
