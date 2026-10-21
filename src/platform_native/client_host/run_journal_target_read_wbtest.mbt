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
  database.insert("client_runs", "unrelated", b"invalid historic row").unwrap()
  |> ignore
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
  assert_eq(calls, ["fenced", "read:client_run_custody:issued"])
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
  database
  .compare_exchange("client_runs", key, row.revision, b"invalid selected row")
  .unwrap()
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
      b"changed selected row",
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
test "fresh Run binding uses local issuance and definition index without unrelated inventory" {
  let database = epoch_test_database("journal-local-append")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  database
  .insert("client_runs", "unrelated", b"unrelated original not selected")
  .unwrap()
  |> ignore
  database
  .insert("client_effect_custody", "unrelated", b"unrelated effect")
  .unwrap()
  |> ignore
  let (request, _, _, definition) = journal_test_run(
    "local-append", "local-append-run",
  )
  let calls : Array[String] = []
  let operations = journal_test_operation_access(database, calls)
  let record = journal
    .transaction_with_reads(
      () => {
        journal.bind_run_locked(
          request,
          definition,
          operations=Some(operations),
        )
      },
      reads=Some(operations.reads),
    )
    .unwrap()
  assert_false(calls.any(value => value.has_prefix("scan:")))
  assert_eq(database.read("client_run_custody", "issued").unwrap().body, b"1")
  assert_eq(
    database.read("client_run_append_coverage", "issued").unwrap().body,
    b"1:1",
  )
  assert_eq(
    database
    .read(
      "client_run_definition_index",
      @publication.publication_contract_identity(definition),
    )
    .unwrap().body,
    @utf8.encode(@host.client_request_scope_cid(record.request)),
  )
  assert_true(run_journal_custody(database, 8) is Err(CustodyLost))
  database.close_checked().unwrap()
}

///|
test "legacy Run append requires explicit complete indexing and retains duplicate refusal" {
  let database = epoch_test_database("journal-legacy-append")
  initialize_native_client_run_journal(database).unwrap()
  initialize_native_client_submitted_intents(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "legacy-append", "legacy-append-run",
  )
  let original = journal
    .bind_run(request, prepared, compiled, definition, true)
    .unwrap()
  let coverage = database.read("client_run_append_coverage", "issued").unwrap()
  database
  .compare_exchange(
    "client_run_append_coverage",
    "issued",
    coverage.revision,
    b"0:0",
  )
  .unwrap()
  |> ignore
  let (next, next_prepared, next_compiled, next_definition) = journal_test_run(
    "legacy-next", "legacy-next-run",
  )
  assert_true(
    journal.bind_run(next, next_prepared, next_compiled, next_definition, true)
    is Err(CustodyLost),
  )
  assert_eq(database.read("client_run_custody", "issued").unwrap().body, b"1")
  journal
  .transaction(() => journal.index_legacy_append_metadata_locked())
  .unwrap()
  assert_eq(
    database.read("client_run_append_coverage", "issued").unwrap().body,
    b"1:1",
  )
  assert_true(
    journal.transaction(() => journal.bind_run_locked(next, original.definition))
    is Err(ForeignRun),
  )
  journal
  .bind_run(next, next_prepared, next_compiled, next_definition, true)
  .unwrap()
  |> ignore
  assert_eq(database.read("client_run_custody", "issued").unwrap().body, b"2")
  database.close_checked().unwrap()
}

///|
test "definition index insertion failure restores the original Run count and coverage" {
  let database = epoch_test_database("journal-index-rollback")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, _, _, definition) = journal_test_run(
    "index-rollback", "index-rollback-run",
  )
  let calls : Array[String] = []
  let operations : NativeClientJournalOperationAccess = {
    ..journal_test_operation_access(database, calls),
    insert: (table, key, body) => {
      calls.push("insert:" + table)
      if table == "client_run_definition_index" {
        Err(@sqlite.Busy)
      } else {
        database.insert(table, key, body)
      }
    },
  }
  assert_true(
    journal.transaction_with_reads(
      () => {
        journal.bind_run_locked(
          request,
          definition,
          operations=Some(operations),
        )
      },
      reads=Some(operations.reads),
    )
    is Err(Physical(@sqlite.Busy)),
  )
  assert_true(calls.contains("insert:client_runs"))
  assert_true(calls.contains("insert:client_run_definition_index"))
  assert_eq(calls[calls.length() - 1], "rollback")
  assert_eq(database.read("client_run_custody", "issued").unwrap().body, b"0")
  assert_eq(
    database.read("client_run_append_coverage", "issued").unwrap().body,
    b"0:0",
  )
  assert_true(
    database.read("client_runs", @host.client_request_scope_cid(request))
    is Err(@sqlite.NotFound),
  )
  database.close_checked().unwrap()
}

///|
test "changed selected definition moves its exact locator with the original Run CAS" {
  let database = epoch_test_database("journal-definition-mutation")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "definition-mutation", "original-definition",
  )
  let original = journal
    .bind_run(request, prepared, compiled, definition, true)
    .unwrap()
  let (_, _, _, replacement) = journal_test_run(
    "definition-mutation", "replacement-definition",
  )
  let calls : Array[String] = []
  let operations = journal_test_operation_access(database, calls)
  let next = journal
    .transaction_with_reads(
      () => {
        journal.save_with_operations(
          { ..original, definition: replacement, },
          operations=Some(operations),
        )
      },
      reads=Some(operations.reads),
    )
    .unwrap()
  assert_eq(next.revision, original.revision + 1L)
  assert_false(calls.any(value => value.has_prefix("scan:")))
  assert_true(
    database.read(
      "client_run_definition_index",
      @publication.publication_contract_identity(definition),
    )
    is Err(@sqlite.NotFound),
  )
  assert_eq(
    database
    .read(
      "client_run_definition_index",
      @publication.publication_contract_identity(replacement),
    )
    .unwrap().body,
    @utf8.encode(@host.client_request_scope_cid(request)),
  )
  let (other, _, _, _) = journal_test_run("different-request", "different-run")
  assert_true(
    journal.transaction(() => journal.bind_run_locked(other, replacement))
    is Err(ForeignRun),
  )
  database.close_checked().unwrap()
}

///|
test "definition locator mutation failure restores the original Run and both locator identities" {
  let database = epoch_test_database("journal-definition-mutation-rollback")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "definition-rollback", "original-definition",
  )
  let original = journal
    .bind_run(request, prepared, compiled, definition, true)
    .unwrap()
  let (_, _, _, replacement) = journal_test_run(
    "definition-rollback", "replacement-definition",
  )
  let calls : Array[String] = []
  let operations : NativeClientJournalOperationAccess = {
    ..journal_test_operation_access(database, calls),
    insert: (table, key, body) => {
      if table == "client_run_definition_index" {
        Err(@sqlite.Busy)
      } else {
        database.insert(table, key, body)
      }
    },
  }
  assert_true(
    journal.transaction_with_reads(
      () => {
        journal.save_with_operations(
          { ..original, definition: replacement, },
          operations=Some(operations),
        )
      },
      reads=Some(operations.reads),
    )
    is Err(Physical(@sqlite.Busy)),
  )
  assert_eq(calls[calls.length() - 1], "rollback")
  let restored = journal.lookup(request, true).unwrap()
  guard restored is Retained(restored) else { fail("original Run lost") }
  assert_eq(restored.revision, original.revision)
  assert_eq(
    @publication.publication_contract_identity(restored.definition),
    @publication.publication_contract_identity(definition),
  )
  assert_eq(
    database
    .read(
      "client_run_definition_index",
      @publication.publication_contract_identity(definition),
    )
    .unwrap().body,
    @utf8.encode(@host.client_request_scope_cid(request)),
  )
  assert_true(
    database.read(
      "client_run_definition_index",
      @publication.publication_contract_identity(replacement),
    )
    is Err(@sqlite.NotFound),
  )
  database.close_checked().unwrap()
}
