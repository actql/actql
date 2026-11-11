///|
test "Native original Effect Submission is admitted without reserving or starting work" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "client-submitted-effect-admission",
  )
  let scope = "sha256:" + "a".repeat(64)
  let (intent, preparation, request, allowed, definition) = native_client_effect_fixture_input(
    reference, "original-effect-run",
  )
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  let original = journal
    .accept_submitted_effect_run(
      authority, reference, preparation, request, allowed, definition, scope, true,
      1002.0,
    )
    .unwrap()
  guard original.run_admission is Some(admission) else {
    fail("original Effect admission missing")
  }
  assert_eq(
    admission.run_definition_cid,
    @publication.publication_contract_identity(definition),
  )
  assert_eq(admission.revision, 0L)
  guard journal.lookup(request, true) is Ok(Retained(before)) else {
    fail("original Effect Run missing")
  }
  assert_false(before.dispatch_reserved)
  assert_false(before.physical_start_claimed)
  assert_true(before.checkpoint is None)
  guard before.run_observation_originals is Some(observation_wire) else {
    fail("original Effect admission omitted observation originals")
  }
  let observation = read_native_run_observation_originals(
    observation_wire, definition,
  ).unwrap()
  assert_eq(
    @publication.run_evidence_value_json(observation.prepared()),
    @publication.run_evidence_value_json(
      @host.client_effect_allowed_run_prepared(allowed),
    ),
  )
  assert_eq(
    @publication.run_evidence_value_json(observation.authorization()),
    @publication.run_evidence_value_json(
      @host.client_effect_allowed_run_authorization(allowed),
    ),
  )
  assert_eq(run_journal_custody(database, 8).unwrap().0, 1)
  let repeated = journal
    .accept_submitted_effect_run(
      authority, reference, preparation, request, allowed, definition, scope, true,
      1003.0,
    )
    .unwrap()
  assert_eq(repeated.revision, original.revision)
  database.close_checked().unwrap()
  let database = epoch_test_database("client-submitted-effect-admission")
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let authority = open_native_client_epoch_authority(
    database,
    epoch_test_crypto(),
    100.0,
  ).unwrap()
  guard journal.lookup_submitted_intent(
      authority, reference, scope, true, 1100.0,
    )
    is Ok(Submitted(restored)) &&
    restored.run_admission is Some(admission) else {
    fail("expired original reference lost the accepted Effect Run")
  }
  assert_eq(
    admission.run_definition_cid,
    @publication.publication_contract_identity(definition),
  )
  assert_eq(admission.revision, 0L)
  assert_eq(admission.request, request)
  guard journal.lookup(admission.request, true) is Ok(Retained(after)) else {
    fail("original Effect Run missing after reopen")
  }
  assert_eq(after.revision, before.revision)
  assert_false(after.dispatch_reserved)
  assert_false(after.physical_start_claimed)
  assert_eq(run_journal_custody(database, 8).unwrap().0, 1)
  database.close_checked().unwrap()
}

///|
test "Native Effect acceptance refuses another owner changed input and a replacement Run" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "client-submitted-effect-refusals",
  )
  let scope = "sha256:" + "a".repeat(64)
  let (intent, preparation, request, allowed, definition) = native_client_effect_fixture_input(
    reference, "original-effect-run",
  )
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  assert_true(
    journal.accept_submitted_effect_run(
      authority, reference, preparation, request, allowed, definition, scope, false,
      1002.0,
    )
    is Err(AuthorizationDenied),
  )
  let (_, foreign_preparation, _, foreign_allowed, _) = native_client_effect_fixture_input(
    reference, "original-effect-run",
  )
  assert_eq(preparation.intent_cid, foreign_preparation.intent_cid)
  assert_true(
    journal.accept_submitted_effect_run(
      authority, reference, preparation, request, foreign_allowed, definition, scope,
      true, 1002.0,
    )
    is Err(ChangedIntent),
  )
  let foreign_reference = prepare_native_client_submission_reference(
    reference.epoch,
    "other-submit",
  ).unwrap()
  assert_true(
    journal.accept_submitted_effect_run(
      authority, foreign_reference, preparation, request, allowed, definition, scope,
      true, 1002.0,
    )
    is Err(InvalidSubmission),
  )
  assert_true(
    journal.accept_submitted_effect_run(
      authority,
      reference,
      preparation,
      request,
      allowed,
      definition,
      "sha256:" + "f".repeat(64),
      true,
      1002.0,
    )
    is Err(InvalidSubmission),
  )
  let (
    _,
    changed_preparation,
    changed_request,
    changed_allowed,
    changed_definition,
  ) = native_client_effect_fixture_input(
    reference,
    "changed-effect-run",
    document=native_client_effect_fixture_document.replace(
      old="e\\u0301\\r\\n",
      new="é\\r\\n",
    ),
  )
  assert_true(changed_preparation.intent_cid != preparation.intent_cid)
  assert_true(
    journal.accept_submitted_effect_run(
      authority, reference, changed_preparation, changed_request, changed_allowed,
      changed_definition, scope, true, 1002.0,
    )
    is Err(ChangedIntent),
  )
  assert_eq(run_journal_custody(database, 8).unwrap().0, 0)
  guard journal.lookup_submitted_intent(
      authority, reference, scope, true, 1003.0,
    )
    is Ok(Submitted(original)) else {
    fail("original intent lost")
  }
  assert_true(original.run_admission is None)
  journal
  .accept_submitted_effect_run(
    authority, reference, preparation, request, allowed, definition, scope, true,
    1004.0,
  )
  .unwrap()
  |> ignore
  let replacement = @host.issue_client_effect_run_definition(
    allowed, "local-test", "replacement-effect-run", "2026-10-10T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(
    journal.accept_submitted_effect_run(
      authority, reference, preparation, request, allowed, replacement, scope, true,
      1005.0,
    )
    is Err(ForeignRun),
  )
  assert_eq(run_journal_custody(database, 8).unwrap().0, 1)
  database.close_checked().unwrap()
}

///|
test "Native ordinary and Effect acceptance do not fall back between checked owners" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "client-submitted-effect-no-fallback",
  )
  let scope = "sha256:" + "a".repeat(64)
  let (_, preparation, request, allowed, definition) = native_client_effect_fixture_input(
    reference, "original-effect-run",
  )
  let (_, ordinary, ordinary_request, ordinary_compiled, ordinary_definition) = submitted_run_test_input(
    reference, "ordinary-run",
  )
  assert_true(
    journal.accept_submitted_run(
      authority, reference, preparation, request, ordinary_compiled, definition,
      scope, true, 1001.0,
    )
    is Err(UnsupportedPreparation),
  )
  assert_true(
    journal.accept_submitted_effect_run(
      authority, reference, ordinary, ordinary_request, allowed, ordinary_definition,
      scope, true, 1001.0,
    )
    is Err(UnsupportedPreparation),
  )
  assert_eq(run_journal_custody(database, 8).unwrap().0, 0)
  database.close_checked().unwrap()
}

///|
test "Native Effect acceptance distinguishes precommit failure and lost committed reply across reopen" {
  for reply_lost in [false, true] {
    let name = "client-submitted-effect-commit-" + reply_lost.to_string()
    let (database, journal, authority, reference) = submitted_test_setup(name)
    let scope = "sha256:" + "a".repeat(64)
    let (intent, preparation, request, allowed, definition) = native_client_effect_fixture_input(
      reference, "original-effect-run",
    )
    journal
    .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
    .unwrap()
    |> ignore
    // The first commit is the epoch watermark, the second is the same
    // original Submission/Run transaction used by ordinary computation.
    submitted_test_fail_commit_after(database, 1, reply_lost)
    assert_true(
      journal.accept_submitted_effect_run(
        authority, reference, preparation, request, allowed, definition, scope, true,
        1002.0,
      )
      is Err(TransactionUnknown),
    )
    assert_true(database.transaction_fenced())
    if !reply_lost {
      database.rollback().unwrap()
    }
    database.close_checked().unwrap()
    let database = epoch_test_database(name)
    let journal = open_native_client_run_journal(database, 8).unwrap()
    let authority = open_native_client_epoch_authority(
      database,
      epoch_test_crypto(),
      100.0,
    ).unwrap()
    guard journal.lookup_submitted_intent(
        authority, reference, scope, true, 1003.0,
      )
      is Ok(Submitted(original)) else {
      fail("original Effect intent disappeared")
    }
    if reply_lost {
      guard original.run_admission is Some(admission) else {
        fail("committed Effect admission missing")
      }
      assert_eq(admission.request, request)
      assert_eq(
        admission.run_definition_cid,
        @publication.publication_contract_identity(definition),
      )
      guard journal.lookup(request, true) is Ok(Retained(run)) else {
        fail("committed Run missing")
      }
      assert_false(run.dispatch_reserved)
      assert_false(run.physical_start_claimed)
      assert_eq(run_journal_custody(database, 8).unwrap().0, 1)
    } else {
      assert_true(original.run_admission is None)
      assert_true(journal.lookup(request, true) is Ok(UnresolvedHistory))
      assert_eq(run_journal_custody(database, 8).unwrap().0, 0)
    }
    assert_eq(journal.submitted_intent_custody().unwrap().0, 1)
    database.close_checked().unwrap()
  }
}

///|
test "Native missing intent and finite capacity cannot issue an Effect Run" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "client-submitted-effect-capacity",
    max_records=1,
  )
  let scope = "sha256:" + "a".repeat(64)
  let (intent, preparation, request, allowed, definition) = native_client_effect_fixture_input(
    reference, "original-effect-run",
  )
  assert_true(
    journal.accept_submitted_effect_run(
      authority, reference, preparation, request, allowed, definition, scope, true,
      1001.0,
    )
    is Err(CustodyLost),
  )
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1002.0)
  .unwrap()
  |> ignore
  let (other, prepared, compiled, other_definition) = journal_test_run(
    "other-submit", "other-run",
  )
  journal.bind_run(other, prepared, compiled, other_definition, true).unwrap()
  |> ignore
  assert_true(
    journal.accept_submitted_effect_run(
      authority, reference, preparation, request, allowed, definition, scope, true,
      1003.0,
    )
    is Err(CapacityExceeded),
  )
  guard journal.lookup_submitted_intent(
      authority, reference, scope, true, 1004.0,
    )
    is Ok(Submitted(original)) else {
    fail("original intent missing")
  }
  assert_true(original.run_admission is None)
  assert_true(journal.lookup(request, true) is Ok(UnresolvedHistory))
  assert_eq(run_journal_custody(database, 1).unwrap().0, 1)
  database.close_checked().unwrap()
}

///|
test "Native accepted Effect with lost original Run custody refuses selected lookup and integrity inspection" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "client-submitted-effect-lost-custody",
  )
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
  let table = @utf8.encode("client_runs")
  let key = @utf8.encode(@host.client_request_scope_cid(request))
  assert_true(
    submitted_test_remove_record(
      database,
      table,
      table.length(),
      key,
      key.length(),
    ),
  )
  assert_true(
    journal.lookup_submitted_intent(authority, reference, scope, true, 1003.0)
    is Err(CustodyLost),
  )
  assert_true(open_native_client_run_journal(database, 8) is Ok(_))
  assert_true(run_journal_custody(database, 8) is Err(CustodyLost))
  assert_true(
    database.read("client_runs", @host.client_request_scope_cid(request))
    is Err(@sqlite.NotFound),
  )
  assert_true(
    journal.accept_submitted_effect_run(
      authority, reference, preparation, request, allowed, definition, scope, true,
      1004.0,
    )
    is Err(CustodyLost),
  )
  database.close_checked().unwrap()
}
