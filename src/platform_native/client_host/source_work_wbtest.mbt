///|
test "Native Local work guard never grants two physical starts for an original Run" {
  let database = epoch_test_database("client-work-start")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "original-request", "original-run",
  )
  assert_false(@resident.resident_source_compute_shape_supported(prepared))
  assert_true(
    claim_native_client_work_start(
      journal,
      request,
      prepared,
      compiled,
      definition,
      () => true,
    )
    is Ok(_),
  )
  assert_true(
    claim_native_client_work_start(
      journal,
      request,
      prepared,
      compiled,
      definition,
      () => true,
    )
    is Err(NeedsOriginalReconciliation),
  )
  database.close_checked().unwrap()
  let reopened = epoch_test_database("client-work-start")
  let journal = open_native_client_run_journal(reopened, 8).unwrap()
  assert_true(
    claim_native_client_work_start(
      journal,
      request,
      prepared,
      compiled,
      definition,
      () => true,
    )
    is Err(NeedsOriginalReconciliation),
  )
  let (_, _, _, replacement) = journal_test_run("original-request", "new-run")
  assert_true(
    claim_native_client_work_start(
      journal,
      request,
      prepared,
      compiled,
      replacement,
      () => true,
    )
    is Err(Journal(ForeignRun)),
  )
  reopened.close_checked().unwrap()
}

///|
test "Native Local work guard rechecks current authority across every durable boundary" {
  // Each callback independently loses authority at one boundary. The expected
  // original binding/reservation/claim state is authored, not derived from the
  // operation's output. No provider or physical work is invoked by this guard.
  for denied_at in 1..<=4 {
    let name = "client-work-authority-" + denied_at.to_string()
    let database = epoch_test_database(name)
    initialize_native_client_run_journal(database).unwrap()
    let journal = open_native_client_run_journal(database, 8).unwrap()
    let (request, prepared, compiled, definition) = journal_test_run(
      "original-request", "original-run",
    )
    let mut calls = 0
    let outcome = claim_native_client_work_start(
      journal,
      request,
      prepared,
      compiled,
      definition,
      () => {
        calls = calls + 1
        calls != denied_at
      },
    )
    assert_true(outcome is Err(AuthorizationDenied))
    assert_eq(calls, denied_at)
    if denied_at == 1 {
      assert_true(journal.lookup(request, true) is Ok(UnresolvedHistory))
    } else {
      guard journal.lookup(request, true) is Ok(Retained(record)) else {
        fail("original binding missing")
      }
      assert_eq(record.dispatch_reserved, denied_at >= 3)
      assert_eq(record.physical_start_claimed, denied_at >= 4)
    }
    database.close_checked().unwrap()
  }
}

///|
test "Native Local work guard observes cancellation accepted by its final authority callback" {
  let database = epoch_test_database("client-work-cancellation-callback")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "original-request", "original-run",
  )
  let mut callbacks = 0
  let mut accepted = false
  let outcome = claim_native_client_work_start(
    journal,
    request,
    prepared,
    compiled,
    definition,
    () => {
      callbacks = callbacks + 1
      if callbacks == 4 {
        journal
        .transaction(() => {
          let record = journal.retained(request).unwrap().unwrap()
          let action = @host.prepare_client_run_cancellation(
            record.definition,
            @publication.publication_contract_identity(definition),
            true,
            false,
            record.cancellation_requested,
          ).unwrap()
          accepted = action == @host.AcceptCancellation
          journal.save({ ..record, cancellation_requested: true, }).map(_ => ())
        })
        .unwrap()
      }
      true
    },
  )
  assert_true(accepted)
  assert_true(outcome is Err(NeedsOriginalReconciliation))
  guard journal.lookup(request, true) is Ok(Retained(record)) else {
    fail("original cancelled intent missing")
  }
  // These remain independent durable facts, not a Cancelled terminal or proof
  // of physical stop/cleanup. The guard supplies no acquisition permit.
  assert_true(record.dispatch_reserved)
  assert_true(record.physical_start_claimed)
  assert_true(record.cancellation_requested)
  assert_false(journal.claim_physical_start(request, true).unwrap())
  database.close_checked().unwrap()
}
