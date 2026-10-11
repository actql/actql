///|
// Compile-only Native boundary definitions. The admitted Source-free fixture
// tests original start facts, not target observation or a checked read grant.
test "Native preparation first-start witness is operational and cannot be reminted from retained flags" {
  let (database, journal, request, allowed, definition) = accepted_effect_work_fixture(
    "preparation-first-start",
  )
  let (_, token) = claim_native_client_effect_work_start(
    journal,
    request,
    allowed,
    definition,
    () => true,
  ).unwrap()
  assert_eq(
    token.definition_cid,
    @publication.publication_contract_identity(definition),
  )
  assert_eq(
    @host.client_request_intent_cid(token.request),
    @host.client_request_intent_cid(request),
  )
  assert_true(token.require_current(journal, request, () => true) is Ok(_))
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
  assert_true(
    token.require_current(journal, request, () => false)
    is Err(AuthorizationDenied),
  )
  let (_, _, _, foreign_definition) = journal_test_run("foreign", "foreign")
  let (foreign, _, _, _) = journal_test_run("foreign-request", "foreign-run")
  assert_true(
    token.require_current(journal, foreign, () => true)
    is Err(Journal(ForeignRun)),
  )
  assert_false(
    token.definition_cid ==
    @publication.publication_contract_identity(foreign_definition),
  )
  database.close_checked().unwrap()
  let reopened = epoch_test_database("preparation-first-start")
  let restored = open_native_client_run_journal(reopened, 8).unwrap()
  assert_true(
    claim_native_client_effect_work_start(
      restored,
      request,
      allowed,
      definition,
      () => true,
    )
    is Err(NeedsOriginalReconciliation),
  )
  assert_true(
    token.require_current(restored, request, () => true)
    is Err(Journal(ForeignRun)),
  )
  reopened.close_checked().unwrap()
}

///|
test "Native preparation first-start denies token on final authority loss or unknown commit" {
  for unknown in [false, true] {
    let (database, journal, request, allowed, definition) = accepted_effect_work_fixture(
      "preparation-denied-" + unknown.to_string(),
    )
    let mut injected = false
    let current = () => {
      guard journal.lookup(request, true) is Ok(Retained(record)) else {
        return false
      }
      if unknown &&
        record.dispatch_reserved &&
        !record.physical_start_claimed &&
        !injected {
        injected = true
        client_test_fail_commit_reply(database, 1)
      }
      unknown || !record.physical_start_claimed
    }
    let result = claim_native_client_effect_work_start(
      journal, request, allowed, definition, current,
    )
    if unknown {
      assert_true(result is Err(Journal(TransactionUnknown)))
    } else {
      assert_true(result is Err(AuthorizationDenied))
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
    database.close_checked().unwrap()
  }
}

///|
test "Native retained preparation start witness refuses cancellation accepted during a current callback" {
  let (database, journal, request, allowed, definition) = accepted_effect_work_fixture(
    "preparation-current-cancel",
  )
  let (_, token) = claim_native_client_effect_work_start(
    journal,
    request,
    allowed,
    definition,
    () => true,
  ).unwrap()
  let mut accepted = false
  let current = () => {
    if !accepted {
      journal
      .transaction(() => {
        let record = journal.retained(request).unwrap().unwrap()
        accepted = true
        journal.save({ ..record, cancellation_requested: true, }).map(_ => ())
      })
      .unwrap()
    }
    true
  }
  assert_true(
    token.require_current(journal, request, current)
    is Err(NeedsOriginalReconciliation),
  )
  assert_true(accepted)
  assert_true(
    token.require_current(journal, request, () => true)
    is Err(NeedsOriginalReconciliation),
  )
  guard journal.lookup(request, true) is Ok(Retained(record)) else {
    fail("original cancelled preparation Work missing")
  }
  assert_true(record.physical_start_claimed)
  assert_true(record.cancellation_requested)
  assert_true(record.checkpoint is None)
  assert_false(journal.claim_physical_start(request, true).unwrap())
  // Cancellation acceptance is not physical-stop or terminal cleanup evidence.
  assert_eq(
    @publication.publication_contract_identity(record.definition),
    @publication.publication_contract_identity(definition),
  )
  database.close_checked().unwrap()
}
