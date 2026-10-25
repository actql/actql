///|
// Real Journal rows and observed SQLite calls. This does not supply an
// installed Host pair, Account decision, or physical Read lifetime.
fn submission_operation_fixture(
  name : String,
) -> (
  @sqlite.Database,
  NativeClientRunJournal,
  NativeClientEpochAuthority,
  NativeClientSubmissionReference,
  @host.ClientRequestIdentity,
) raise {
  let (database, journal, authority, reference) = submitted_test_setup(name)
  let (intent, preparation, request, compiled, definition) = submitted_run_test_input(
    reference,
    name + "-run",
  )
  let scope = "sha256:" + "a".repeat(64)
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  journal
  .accept_submitted_run(
    authority, reference, preparation, request, compiled, definition, scope, true,
    1002.0,
  )
  .unwrap()
  |> ignore
  (database, journal, authority, reference, request)
}

///|
test "one unchanged command admits its selected Submission once and observes actual Run mutation" {
  let (database, journal, authority, reference, request) = submission_operation_fixture(
    "submission-operation-once",
  )
  let calls : Array[String] = []
  let reads = journal_test_read_access(database, calls)
  journal.operation_active = true
  let first = journal
    .retained_submission_with_run(reference, reads=Some(reads))
    .unwrap()
    .unwrap()
  assert_eq(
    calls
    .filter(value => {
      value == "read:client_submitted_intents:" + reference.request_id
    })
    .length(),
    1,
  )
  calls.clear()
  for _ in 0..<8 {
    let next = journal
      .retained_submission_with_run(reference, reads=Some(reads))
      .unwrap()
      .unwrap()
    assert_true(physical_equal(first.0, next.0))
    assert_true(physical_equal(first.1.unwrap(), next.1.unwrap()))
  }
  assert_true(calls.all(value => value == "fenced"))
  assert_true(
    journal.reserve_dispatch(request, true).unwrap() is @host.ReserveDispatch,
  )
  calls.clear()
  let changed = journal
    .retained_submission_with_run(reference, reads=Some(reads))
    .unwrap()
    .unwrap()
  assert_true(physical_equal(first.0, changed.0))
  assert_true(changed.1.unwrap().dispatch_reserved)
  assert_eq(changed.1.unwrap().revision, first.1.unwrap().revision + 1L)
  assert_false(
    calls.contains("read:client_submitted_intents:" + reference.request_id),
  )
  assert_eq(
    calls
    .filter(value => {
      value == "read:client_runs:" + @host.client_request_scope_cid(request)
    })
    .length(),
    0,
  )
  // The successful control CAS retained its exact emitted row. Inspect the
  // durable fixture separately; a pure getter must not select it a second time.
  let stored = read_run_record(
    database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap(),
  ).unwrap()
  assert_true(stored.dispatch_reserved)
  assert_eq(stored.revision, changed.1.unwrap().revision)
  journal.operation_active = false
  journal.invalidate_operation_record()
  journal.operation_active = true
  calls.clear()
  journal.retained_submission_with_run(reference, reads=Some(reads)).unwrap()
  |> ignore
  assert_eq(
    calls
    .filter(value => {
      value == "read:client_submitted_intents:" + reference.request_id
    })
    .length(),
    1,
  )
  journal.operation_active = false
  journal.invalidate_operation_record()
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}

///|
test "command Submission lookup keeps one anchor and target without read transactions" {
  let (database, journal, authority, reference, request) = submission_operation_fixture(
    "submission-command-lookup",
  )
  let scope = "sha256:" + "a".repeat(64)
  let calls : Array[String] = []
  let operations = journal_test_operation_access(database, calls)
  authority.begin_operation(false)
  journal.operation_active = true
  for _ in 0..<8 {
    assert_true(
      journal.lookup_submitted_intent_with_operations(
        authority,
        reference,
        scope,
        true,
        1002.0,
        operations=Some(operations),
      )
      is Ok(Submitted(_)),
    )
  }
  // The only BEGIN/COMMIT observes the original epoch clock. A stable
  // acknowledged clock and repeated selected-row reads create no new one.
  assert_eq(calls.filter(value => value == "begin").length(), 1)
  assert_eq(calls.filter(value => value == "commit").length(), 1)
  for
    selected in [
      "read:client_submitted_intent_custody:issued",
      "read:client_submitted_intents:" + reference.request_id,
      "read:client_runs:" + @host.client_request_scope_cid(request),
    ] {
    assert_eq(calls.filter(value => value == selected).length(), 1)
  }
  calls.clear()
  assert_true(
    journal.lookup_submitted_intent_with_operations(
      authority,
      reference,
      scope,
      false,
      1002.0,
      operations=Some(operations),
    )
    is Err(AuthorizationDenied),
  )
  assert_eq(calls, [])
  assert_true(
    journal.reserve_dispatch(request, true).unwrap() is @host.ReserveDispatch,
  )
  calls.clear()
  guard journal.lookup_submitted_intent_with_operations(
      authority,
      reference,
      scope,
      true,
      1002.0,
      operations=Some(operations),
    )
    is Ok(Submitted(updated)) else {
    fail("lost original Submission")
  }
  assert_true(updated.run_admission is Some(_))
  assert_true(
    journal.operation_submission.unwrap().1.unwrap().dispatch_reserved,
  )
  assert_eq(
    calls.filter(value => value.has_prefix("read:client_runs:")).length(),
    0,
  )
  let stored = read_run_record(
    database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap(),
  ).unwrap()
  assert_true(stored.dispatch_reserved)
  assert_eq(
    stored.revision,
    journal.operation_submission.unwrap().1.unwrap().revision,
  )
  assert_false(calls.contains("begin"))
  assert_false(
    calls.contains("read:client_submitted_intent_custody:issued") ||
    calls.contains("read:client_submitted_intents:" + reference.request_id),
  )
  journal.operation_active = false
  journal.invalidate_operation_record()
  authority.end_operation()
  calls.clear()
  assert_true(
    journal.lookup_submitted_intent_with_operations(
      authority,
      reference,
      scope,
      true,
      1002.0,
      operations=Some(operations),
    )
    is Ok(Submitted(_)),
  )
  // Standalone callers retain both original transactions and fresh target
  // admission; no operation fact or permission survives the previous end.
  assert_eq(calls.filter(value => value == "begin").length(), 2)
  assert_eq(calls.filter(value => value == "commit").length(), 2)
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}

///|
test "command Submission lookup preserves epoch failure and actual anchor invalidation" {
  let (database, journal, authority, reference, _) = submission_operation_fixture(
    "submission-command-invalid",
  )
  let scope = "sha256:" + "a".repeat(64)
  let calls : Array[String] = []
  let failed = Ref(false)
  let operations : NativeClientJournalOperationAccess = {
    ..journal_test_operation_access(database, calls),
    reads: {
      ..journal_test_read_access(database, calls),
      fenced: () => failed.val || database.transaction_fenced(),
    },
  }
  authority.begin_operation(false)
  journal.operation_active = true
  assert_true(
    journal.lookup_submitted_intent_with_operations(
      authority,
      reference,
      scope,
      true,
      1002.0,
      operations=Some(operations),
    )
    is Ok(Submitted(_)),
  )
  failed.val = true
  assert_true(
    journal.lookup_submitted_intent_with_operations(
      authority,
      reference,
      scope,
      true,
      1002.0,
      operations=Some(operations),
    )
    is Err(Epoch(Fenced)),
  )
  assert_true(journal.operation_submission is None)
  failed.val = false
  assert_true(
    journal.lookup_submitted_intent_with_operations(
      authority,
      reference,
      scope,
      true,
      1002.0,
      operations=Some(operations),
    )
    is Err(Epoch(Fenced)),
  )
  journal.operation_active = false
  journal.invalidate_operation_record()
  authority.end_operation()
  let anchor = database
    .read("client_submitted_intent_custody", "issued")
    .unwrap()
  database.begin_immediate().unwrap()
  database
  .compare_exchange(
    "client_submitted_intent_custody",
    "issued",
    anchor.revision,
    b"corrupt",
  )
  .unwrap()
  |> ignore
  database.commit().unwrap()
  journal.operation_active = true
  authority.begin_operation(false)
  calls.clear()
  assert_true(
    journal.lookup_submitted_intent_with_operations(
      authority,
      reference,
      scope,
      true,
      1002.0,
      operations=Some(operations),
    )
    is Err(CustodyLost),
  )
  assert_true(journal.operation_submission is None)
  assert_false(
    calls.contains("read:client_submitted_intents:" + reference.request_id),
  )
  journal.operation_active = false
  journal.invalidate_operation_record()
  authority.end_operation()
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}

///|
test "failed original lifetime and foreign SQL access cannot revive a retained Submission" {
  let (database, journal, authority, reference, _) = submission_operation_fixture(
    "submission-operation-failure",
  )
  let calls : Array[String] = []
  let failed = Ref(false)
  let reads : NativeClientJournalReadAccess = {
    ..journal_test_read_access(database, calls),
    fenced: () => failed.val || database.transaction_fenced(),
  }
  journal.operation_active = true
  journal.retained_submission_with_run(reference, reads=Some(reads)).unwrap()
  |> ignore
  failed.val = true
  assert_true(
    journal.retained_submission_with_run(reference, reads=Some(reads))
    is Err(Fenced),
  )
  assert_true(journal.operation_submission is None)
  let row = database
    .read("client_submitted_intents", reference.request_id)
    .unwrap()
  database.begin_immediate().unwrap()
  database
  .compare_exchange(
    "client_submitted_intents",
    reference.request_id,
    row.revision,
    b"corrupt",
  )
  .unwrap()
  |> ignore
  database.commit().unwrap()
  failed.val = false
  assert_true(
    journal.retained_submission_with_run(reference, reads=Some(reads))
    is Err(CustodyLost),
  )
  assert_true(journal.operation_submission is None)
  let foreign = epoch_test_database("submission-operation-foreign")
  assert_true(
    journal.retained_submission_with_run(
      reference,
      reads=Some(journal_test_read_access(foreign, [])),
    )
    is Err(Physical(@sqlite.Collision)),
  )
  journal.operation_active = false
  journal.invalidate_operation_record()
  database.close_checked().unwrap()
  foreign.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}
