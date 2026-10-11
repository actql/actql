///|
// These original-Run guards deliberately use a Source-free checked Effect.
// They test acceptance and physical-claim facts, not acquisition support or
// Provider I/O. The consuming Native Source fixture executes the physical path.
fn accepted_effect_work_fixture(
  name : String,
) -> (
  @sqlite.Database,
  NativeClientRunJournal,
  @host.ClientRequestIdentity,
  @host.ClientEffectAllowedRun,
  @publication.PublicationContract,
) raise {
  let (database, journal, authority, reference) = submitted_test_setup(name)
  let scope = "sha256:" + "a".repeat(64)
  let (intent, preparation, request, allowed, definition) = native_client_effect_fixture_input(
    reference, "original-effect-run",
  )
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  journal
  .accept_submitted_effect_run(
    authority, reference, preparation, request, allowed, definition, scope, true,
    1002.0,
  )
  .unwrap()
  |> ignore
  (database, journal, request, allowed, definition)
}

///|
// Original journal/claim records, not Source I/O or physical-cleanup evidence.
// Material lookup must not reopen a cancelled or possibly started original.
test "Native live original materials do not reset cancelled or claimed Effect work" {
  for cancelled in [true, false] {
    let (database, journal, request, allowed, definition) = accepted_effect_work_fixture(
      "original-effect-live-material-" + cancelled.to_string(),
    )
    let prepared = @host.client_effect_compilation_owner(allowed.compilation)
    let issued = @host.issue_prepared_client_effect_normalization_materials(
      allowed,
      definition,
      @host.issue_prepared_client_effect_normalization(prepared).unwrap(),
      request=Some(request),
    ).unwrap()
    if cancelled {
      let record = journal.retained(request).unwrap().unwrap()
      let action = @host.prepare_client_run_cancellation(
        record.definition,
        @publication.publication_contract_identity(definition),
        true,
        false,
        record.cancellation_requested,
      ).unwrap()
      assert_true(action == @host.AcceptCancellation)
      journal
      .transaction(() => {
        let record = journal.retained(request).unwrap().unwrap()
        journal.save({ ..record, cancellation_requested: true, }).map(_ => ())
      })
      .unwrap()
    } else {
      claim_native_client_effect_work_start(
        journal,
        request,
        allowed,
        definition,
        () => true,
      ).unwrap()
      |> ignore
    }
    let before = journal.retained(request).unwrap().unwrap()
    let original = run_record_body(before).unwrap()
    let capacity = run_journal_custody(database, 8).unwrap()
    for _ in 0..<2 {
      let materials = @host.bind_prepared_client_effect_original_materials(
        allowed,
        definition,
        issued,
        request=Some(request),
      ).unwrap()
      assert_true(physical_equal(materials.prepared, prepared))
      assert_true(physical_equal(materials.allowed, allowed))
      assert_eq(materials.request, Some(request))
      assert_eq(
        run_record_body(journal.retained(request).unwrap().unwrap()).unwrap(),
        original,
      )
      assert_eq(run_journal_custody(database, 8).unwrap(), capacity)
      assert_true(
        claim_native_client_effect_work_start(
          journal,
          request,
          materials.allowed,
          materials.run_definition,
          () => true,
        )
        is Err(NeedsOriginalReconciliation),
      )
      assert_eq(
        run_record_body(journal.retained(request).unwrap().unwrap()).unwrap(),
        original,
      )
    }
    database.close_checked().unwrap()
  }
}

///|
test "Native original Effect work claim remains single across journal reopen" {
  let name = "original-effect-single-claim"
  let (database, journal, request, allowed, definition) = accepted_effect_work_fixture(
    name,
  )
  assert_true(
    claim_native_client_effect_work_start(
      journal,
      request,
      allowed,
      definition,
      () => true,
    )
    is Ok(_),
  )
  assert_true(
    claim_native_client_effect_work_start(
      journal,
      request,
      allowed,
      definition,
      () => true,
    )
    is Err(NeedsOriginalReconciliation),
  )
  database.close_checked().unwrap()
  let reopened = epoch_test_database(name)
  let journal = open_native_client_run_journal(reopened, 8).unwrap()
  assert_true(
    claim_native_client_effect_work_start(
      journal,
      request,
      allowed,
      definition,
      () => true,
    )
    is Err(NeedsOriginalReconciliation),
  )
  let replacement = @host.issue_client_effect_run_definition(
    allowed, "local-test", "replacement-effect-run", "2026-10-10T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(
    claim_native_client_effect_work_start(
      journal,
      request,
      allowed,
      replacement,
      () => true,
    )
    is Err(Journal(ForeignRun)),
  )
  assert_eq(run_journal_custody(reopened, 8).unwrap().0, 1)
  reopened.close_checked().unwrap()
}

///|
test "Native original Effect work claim rechecks authority at each durable boundary" {
  for denied_at in 1..<=4 {
    let (database, journal, request, allowed, definition) = accepted_effect_work_fixture(
      "original-effect-authority-" + denied_at.to_string(),
    )
    let mut calls = 0
    assert_true(
      claim_native_client_effect_work_start(
        journal,
        request,
        allowed,
        definition,
        () => {
          calls += 1
          calls != denied_at
        },
      )
      is Err(AuthorizationDenied),
    )
    assert_eq(calls, denied_at)
    guard journal.lookup(request, true) is Ok(Retained(record)) else {
      fail("original accepted Effect Run missing")
    }
    assert_eq(record.dispatch_reserved, denied_at >= 3)
    assert_eq(record.physical_start_claimed, denied_at >= 4)
    assert_false(record.cancellation_requested)
    database.close_checked().unwrap()
  }
}

///|
test "Native original Effect claim refuses cancellation accepted by final callback" {
  let (database, journal, request, allowed, definition) = accepted_effect_work_fixture(
    "original-effect-cancel-callback",
  )
  let mut calls = 0
  let mut accepted = false
  let outcome = claim_native_client_effect_work_start(
    journal,
    request,
    allowed,
    definition,
    () => {
      calls += 1
      if calls == 4 {
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
    fail("original accepted Effect Run missing")
  }
  // Accepted cancellation is not a terminal cancellation or physical cleanup.
  assert_true(record.cancellation_requested)
  assert_true(record.physical_start_claimed)
  assert_false(journal.claim_physical_start(request, true).unwrap())
  database.close_checked().unwrap()
}

///|
test "Native Effect claim cannot construct a missing original accepted Run" {
  let (database, journal, _, reference) = submitted_test_setup(
    "original-effect-missing-run",
  )
  let (_, _, request, allowed, definition) = native_client_effect_fixture_input(
    reference, "original-effect-run",
  )
  assert_true(
    claim_native_client_effect_work_start(
      journal,
      request,
      allowed,
      definition,
      () => true,
    )
    is Err(Journal(CustodyLost)),
  )
  assert_true(journal.lookup(request, true) is Ok(UnresolvedHistory))
  assert_eq(run_journal_custody(database, 8).unwrap().0, 0)
  database.close_checked().unwrap()
}

///|
test "Native original Effect physical claim distinguishes precommit and lost committed reply" {
  for reply_lost in [false, true] {
    let name = "original-effect-claim-reply-" + reply_lost.to_string()
    let (database, journal, request, allowed, definition) = accepted_effect_work_fixture(
      name,
    )
    let mut callbacks = 0
    let outcome = claim_native_client_effect_work_start(
      journal,
      request,
      allowed,
      definition,
      () => {
        callbacks += 1
        // The reservation has committed. Inject at the physical-claim commit,
        // not by elapsed time or at the earlier read-only lookup transaction.
        if callbacks == 3 {
          submitted_test_fail_commit_after(database, 0, reply_lost)
        }
        true
      },
    )
    assert_true(outcome is Err(Journal(TransactionUnknown)))
    assert_eq(callbacks, 3)
    assert_true(database.transaction_fenced())
    if !reply_lost {
      database.rollback().unwrap()
    }
    database.close_checked().unwrap()
    let reopened = epoch_test_database(name)
    let journal = open_native_client_run_journal(reopened, 8).unwrap()
    guard journal.lookup(request, true) is Ok(Retained(record)) else {
      fail("original accepted Effect Run missing after lost reply")
    }
    assert_true(record.dispatch_reserved)
    assert_eq(record.physical_start_claimed, reply_lost)
    assert_eq(
      @publication.publication_contract_identity(record.definition),
      @publication.publication_contract_identity(definition),
    )
    if reply_lost {
      assert_true(
        claim_native_client_effect_work_start(
          journal,
          request,
          allowed,
          definition,
          () => true,
        )
        is Err(NeedsOriginalReconciliation),
      )
    }
    // Neither lookup nor this fixture automatically dispatches after failure.
    assert_eq(run_journal_custody(reopened, 8).unwrap().0, 1)
    reopened.close_checked().unwrap()
  }
}
