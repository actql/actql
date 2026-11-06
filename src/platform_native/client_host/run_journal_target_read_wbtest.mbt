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
  assert_true(calls.contains("fenced"))
  assert_eq(calls.filter(value => value != "fenced"), [
    "run-definition-schema", "read:client_run_custody:issued",
  ])
  calls.clear()
  let actual = reopened
    .lookup_with_reads(request, true, reads=Some(reads))
    .unwrap()
  guard actual is Retained(actual) else { fail("missing selected Run") }
  assert_eq(actual.revision, expected.revision)
  // Cheap actual-handle lifetime checks are not durable-row admission. Count
  // each required row/transaction once without prescribing getter cadence.
  assert_true(calls.contains("fenced"))
  assert_eq(calls.filter(value => value != "fenced"), [
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
    calls.filter(value => value == "read:client_run_custody:issued").length(),
    1,
  )
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
    is Err(ForeignRun),
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
  assert_eq(
    calls
    .filter(value => {
      value ==
      "compare_exchange:client_runs:" + @host.client_request_scope_cid(request)
    })
    .length(),
    1,
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

///|
test "acknowledged control CAS retains the same typed Run originals within the operation" {
  let database = epoch_test_database("journal-control-original-reuse")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "control-request", "control-run",
  )
  journal.operation_active = true
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let original = journal.lookup(request, true).unwrap()
  guard original is Retained(original) else { fail("missing original") }
  assert_true(physical_equal(original.request, request))
  assert_true(physical_equal(original.definition, definition))
  let (next, observed) = journal
    .transaction(() => {
      let next = journal.save({ ..original, dispatch_reserved: true, }).unwrap()
      Ok((next, journal.retained(request).unwrap().unwrap()))
    })
    .unwrap()
  assert_true(physical_equal(next, observed))
  assert_true(physical_equal(next.request, original.request))
  assert_true(physical_equal(next.definition, original.definition))
  let (started, observed) = journal
    .transaction(() => {
      let started = journal
        .save({ ..next, physical_start_claimed: true, })
        .unwrap()
      Ok((started, journal.retained(request).unwrap().unwrap()))
    })
    .unwrap()
  assert_true(physical_equal(started, observed))
  assert_eq(started.revision, original.revision + 2L)
  assert_true(started.physical_start_claimed)
  let row = database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap()
  assert_eq(row.body, run_record_body(started).unwrap())
  assert_eq(row.revision, started.revision)
  journal.operation_active = false
  journal.invalidate_operation_record()
  assert_true(journal.operation_run_identity is None)
  guard journal.lookup(request, true).unwrap() is Retained(fresh) else {
    fail("missing committed original")
  }
  assert_false(physical_equal(started, fresh))
  assert_true(fresh.physical_start_claimed)
  database.close_checked().unwrap()
}

///|
test "changed Run metadata and invalid control shape do not inherit a typed original" {
  let database = epoch_test_database("journal-control-changed-original")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "changed", "changed-run",
  )
  let original = journal
    .bind_run(request, prepared, compiled, definition, true)
    .unwrap()
  let (_, _, _, replacement) = journal_test_run("changed", "replacement-run")
  assert_false(
    run_record_originals_unchanged(original, {
      ..original,
      definition: replacement,
    }),
  )
  assert_false(
    run_record_originals_unchanged(original, {
      ..original,
      publication_policy_originals: Some("{}"),
    }),
  )
  assert_false(
    run_record_originals_unchanged(original, {
      ..original,
      physical_start_claimed: true,
    }),
  )
  journal.operation_active = true
  let (next, admitted, no_original) = journal
    .transaction(() => {
      let next = journal.save({ ..original, definition: replacement, }).unwrap()
      let no_original = journal.admitted_record is None
      Ok((next, journal.retained(request).unwrap().unwrap(), no_original))
    })
    .unwrap()
  assert_true(no_original)
  assert_false(physical_equal(next, admitted))
  assert_true(physical_equal(next.request, admitted.request))
  assert_true(physical_equal(next.definition, admitted.definition))
  assert_eq(
    @publication.publication_contract_identity(admitted.definition),
    @publication.publication_contract_identity(replacement),
  )
  journal.operation_active = false
  journal.invalidate_operation_record()
  database.close_checked().unwrap()
}

///|
test "failed control transaction retires the emitted original before rollback recovery" {
  let database = epoch_test_database("journal-control-rollback")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "rollback", "rollback-run",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  journal.operation_active = true
  let observed = Ref(false)
  let result : Result[Unit, NativeClientRunJournalIssue] = journal.transaction(() => {
    let original = journal.retained(request).unwrap().unwrap()
    journal.save({ ..original, dispatch_reserved: true, }).unwrap() |> ignore
    observed.val = journal.admitted_record is Some(_)
    Err(CustodyLost)
  })
  assert_true(observed.val)
  assert_true(result is Err(CustodyLost))
  assert_true(journal.admitted_record is None)
  assert_true(journal.operation_run_identity is None)
  guard journal.lookup(request, true).unwrap() is Retained(restored) else {
    fail("rollback lost original")
  }
  assert_false(restored.dispatch_reserved)
  assert_eq(restored.revision, 0L)
  journal.operation_active = false
  journal.invalidate_operation_record()
  database.close_checked().unwrap()
}

///|
test "lost control COMMIT retires emitted facts and cannot issue another start" {
  let (database, journal, request) = journal_start_operation_fixture(
    "control-commit-lost",
  )
  journal.reserve_dispatch(request, true).unwrap() |> ignore
  journal.operation_active = true
  let calls : Array[String] = []
  let ordinary = journal_test_read_access(database, calls)
  let reads : NativeClientJournalReadAccess = {
    ..ordinary,
    transaction: operation => {
      if operation is JournalCommit {
        database.commit().unwrap()
        Err(@sqlite.Busy)
      } else {
        (ordinary.transaction)(operation)
      }
    },
  }
  let operations = { ..journal_test_operation_access(database, calls), reads, }
  assert_true(
    journal.claim_physical_start_with_operations(
      request,
      true,
      operations=Some(operations),
    )
    is Err(TransactionUnknown),
  )
  assert_true(journal.admitted_record is None)
  assert_true(journal.operation_run_identity is None)
  assert_true(journal.fenced)
  assert_true(database.transaction_fenced())
  assert_true(journal.claim_physical_start(request, true) is Err(Fenced))
  let row = database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap()
  assert_true(read_run_record(row).unwrap().physical_start_claimed)
  journal.operation_active = false
  database.close_checked().unwrap()
}
