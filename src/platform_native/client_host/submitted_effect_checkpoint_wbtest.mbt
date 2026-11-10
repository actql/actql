///|
fn submitted_effect_checkpoint_artifact(
  database : @sqlite.Database,
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  unit? : String = @host.client_effect_compilation_unit_id(allowed.compilation),
  requirements? : Array[@checkpoint.CheckpointRequirement] = [
    EffectScopeApproved,
  ],
  deadline? : String = "2026-10-11T00:00:00.000Z",
) -> @checkpoint.PersistedCheckpoint raise {
  let artifact = @checkpoint.seal_checkpoint(
    {
      checkpoint_id: "original-checked-effect-review",
      continuation_state_cid: "sha256:" + "2".repeat(64),
      subject: RunUnit(
        run_id=@publication.run_definition_run_id(definition).unwrap(),
        unit_id=unit,
        run_definition_cid=@publication.publication_contract_identity(
          definition,
        ),
      ),
      phase: Commit,
      kind: EffectSet,
      required_artifact_cid: "sha256:" + "3".repeat(64),
      review_projection_cid: "sha256:" + "4".repeat(64),
      requirements,
      reason_code: "effect_review_required",
      human_summary: "Review the original checked Effect",
      created_at: "2026-10-10T00:00:00.000Z",
      expires_at: deadline,
    },
    native_checkpoint_limits(),
  ).unwrap()
  // Explicit metadata custody exercises the Client transaction. These fixture
  // CIDs do not claim real Preview/capture/continuation persistence or a send.
  database
  .insert(
    "test_checkpoint_artifacts",
    artifact.checkpoint_cid,
    @utf8.encode(artifact.wire),
  )
  .unwrap()
  |> ignore
  let wire = @utf8.decode(
    database.read("test_checkpoint_artifacts", artifact.checkpoint_cid).unwrap().body,
  )
  @checkpoint.confirm_checkpoint_persisted(artifact, wire).unwrap()
}

///|
fn submitted_effect_checkpoint_setup(
  name : String,
) -> (
  @sqlite.Database,
  NativeClientRunJournal,
  @host.ClientRequestIdentity,
  @host.ClientEffectAllowedRun,
  @publication.PublicationContract,
  NativeClientRunRecord,
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
  journal.reserve_dispatch(request, true).unwrap() |> ignore
  assert_true(journal.claim_physical_start(request, true).unwrap())
  guard journal.lookup(request, true) is Ok(Retained(before)) else {
    fail("original Effect Run missing")
  }
  (database, journal, request, allowed, definition, before)
}

///|
fn submitted_effect_checkpoint_wait(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  allowed : @host.ClientEffectAllowedRun,
  persisted : @checkpoint.PersistedCheckpoint,
  revision : Int64,
  unknown? : Array[String] = [],
  current? : () -> Bool = () => true,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  journal.wait_effect_checkpoint(
    request,
    allowed,
    persisted,
    revision,
    {
      authorization_context_cid: "sha256:" + "a".repeat(64),
      environment_binding_cid: "sha256:" + "b".repeat(64),
    },
    unknown,
    "2026-10-10T00:00:30.000Z",
    current,
  )
}

///|
test "Native checked Effect waiting keeps the original Run Result inventory and custody on reopen" {
  let name = "client-checked-effect-waiting"
  let (database, journal, request, allowed, definition, before) = submitted_effect_checkpoint_setup(
    name,
  )
  let persisted = submitted_effect_checkpoint_artifact(
    database, allowed, definition,
  )
  let waiting = submitted_effect_checkpoint_wait(
    journal,
    request,
    allowed,
    persisted,
    before.revision,
  ).unwrap()
  assert_eq(waiting.revision, before.revision + 1L)
  let state = native_client_run_checkpoint_state(waiting).unwrap()
  assert_eq(state.run_id, "original-effect-run")
  assert_eq(state.status, @publication.WaitingCheckpoint)
  assert_eq(waiting.checkpoint.unwrap().declared_results, ["published"])
  assert_eq(waiting.checkpoint.unwrap().effect_ledger.length(), 0)
  assert_true(waiting.checkpoint.unwrap().verified_wire is None)
  assert_true(waiting.checkpoint.unwrap().resume_intent_id is None)
  database.close_checked().unwrap()
  let database = epoch_test_database(name)
  let journal = open_native_client_run_journal(database, 8).unwrap()
  guard journal.lookup(request, true) is Ok(Retained(restored)) else {
    fail("original waiting disappeared")
  }
  assert_eq(restored.revision, waiting.revision)
  assert_eq(restored.checkpoint.unwrap().state.wire, state.wire)
  assert_eq(restored.checkpoint.unwrap().artifact.wire, persisted.artifact.wire)
  assert_false(journal.claim_physical_start(request, true).unwrap())
  assert_true(
    submitted_effect_checkpoint_wait(
      journal,
      request,
      allowed,
      persisted,
      restored.revision,
    )
    is Err(Checkpoint(NeedsOriginalContinuation)),
  )
  database.close_checked().unwrap()
}

///|
test "Native checked Effect waiting refuses foreign unit lifetime requirements and unknown names without mutation" {
  let (database, journal, request, allowed, definition, before) = submitted_effect_checkpoint_setup(
    "client-checked-effect-wait-refusals",
  )
  let persisted = submitted_effect_checkpoint_artifact(
    database, allowed, definition,
  )
  assert_true(
    submitted_effect_checkpoint_wait(
      journal,
      request,
      allowed,
      persisted,
      before.revision,
      current=() => false,
    )
    is Err(AuthorizationDenied),
  )
  let wrong_unit = submitted_effect_checkpoint_artifact(
    database,
    allowed,
    definition,
    unit="other-unit",
  )
  assert_true(
    submitted_effect_checkpoint_wait(
      journal,
      request,
      allowed,
      wrong_unit,
      before.revision,
    )
    is Err(Checkpoint(EffectBinding(ForeignSubject))),
  )
  let partial = submitted_effect_checkpoint_artifact(
    database,
    allowed,
    definition,
    requirements=[EffectScopeApproved, PartialApplicationAccepted],
  )
  assert_true(
    submitted_effect_checkpoint_wait(
      journal,
      request,
      allowed,
      partial,
      before.revision,
    )
    is Err(Checkpoint(EffectBinding(UnsupportedReview))),
  )
  let extended = submitted_effect_checkpoint_artifact(
    database,
    allowed,
    definition,
    deadline="2100-01-01T00:00:00.000Z",
  )
  assert_true(
    submitted_effect_checkpoint_wait(
      journal,
      request,
      allowed,
      extended,
      before.revision,
    )
    is Err(Checkpoint(EffectBinding(OriginalLifetime))),
  )
  assert_true(
    submitted_effect_checkpoint_wait(
      journal,
      request,
      allowed,
      persisted,
      before.revision,
      unknown=["nonexistent-effect"],
    )
    is Err(Checkpoint(InvalidMaterial)),
  )
  guard journal.lookup(request, true) is Ok(Retained(after)) else {
    fail("original Run lost")
  }
  assert_eq(after.revision, before.revision)
  assert_true(after.checkpoint is None)
  assert_true(database.scan_after("client_effect_custody", "") is Err(NotFound))
  let waiting = submitted_effect_checkpoint_wait(
    journal,
    request,
    allowed,
    persisted,
    before.revision,
    unknown=["save"],
  ).unwrap()
  assert_eq(waiting.checkpoint.unwrap().unknown_effects, ["save"])
  database.close_checked().unwrap()
}

///|
test "Native checked Effect waiting cannot overwrite a concurrent cancellation revision" {
  let (database, journal, request, allowed, definition, before) = submitted_effect_checkpoint_setup(
    "client-checked-effect-wait-race",
  )
  let persisted = submitted_effect_checkpoint_artifact(
    database, allowed, definition,
  )
  assert_true(
    submitted_effect_checkpoint_wait(
      journal,
      request,
      allowed,
      persisted,
      before.revision,
      current=() => {
        journal
        .transaction(() => {
          journal.save({ ..before, cancellation_requested: true, })
        })
        .unwrap()
        |> ignore
        true
      },
    )
    is Err(Checkpoint(StaleRevision)),
  )
  guard journal.lookup(request, true) is Ok(Retained(cancelled)) else {
    fail("original cancellation lost")
  }
  assert_eq(cancelled.revision, before.revision + 1L)
  assert_true(cancelled.cancellation_requested)
  assert_true(cancelled.checkpoint is None)
  assert_true(
    submitted_effect_checkpoint_wait(
      journal,
      request,
      allowed,
      persisted,
      cancelled.revision,
    )
    is Err(Checkpoint(InvalidMaterial)),
  )
  assert_true(database.scan_after("client_effect_custody", "") is Err(NotFound))
  database.close_checked().unwrap()
}

///|
test "Native checked Effect waiting and its independent witness commit together across reply loss" {
  for reply_lost in [false, true] {
    let name = "client-checked-effect-wait-loss-" + reply_lost.to_string()
    let (database, journal, request, allowed, definition, before) = submitted_effect_checkpoint_setup(
      name,
    )
    let persisted = submitted_effect_checkpoint_artifact(
      database, allowed, definition,
    )
    submitted_test_fail_commit_after(database, 0, reply_lost)
    assert_true(
      submitted_effect_checkpoint_wait(
        journal,
        request,
        allowed,
        persisted,
        before.revision,
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
    guard journal.lookup(request, true) is Ok(Retained(restored)) else {
      fail("original Effect disappeared")
    }
    assert_eq(
      restored.revision,
      before.revision + (if reply_lost { 1L } else { 0L }),
    )
    assert_eq(restored.checkpoint is Some(_), reply_lost)
    if reply_lost {
      let witness = database.scan_after("client_effect_custody", "").unwrap()
      assert_eq(witness.key, @host.client_request_scope_cid(request))
      assert_true(
        database.scan_after("client_effect_custody", witness.key)
        is Err(NotFound),
      )
    } else {
      assert_true(
        database.scan_after("client_effect_custody", "") is Err(NotFound),
      )
    }
    assert_false(journal.claim_physical_start(request, true).unwrap())
    database.close_checked().unwrap()
  }
}

///|
// Actual SQLite transition routing; explicit current/Checkpoint metadata here
// does not certify the installed Read pair, real Preview custody or backing.
test "Native Effect waiting uses one original operation for its transaction read insert and CAS" {
  let (database, journal, request, allowed, definition, before) = submitted_effect_checkpoint_setup(
    "effect-wait-original-operation",
  )
  let persisted = submitted_effect_checkpoint_artifact(
    database, allowed, definition,
  )
  let calls : Array[String] = []
  let access = journal_test_operation_access(database, calls)
  let waiting = journal
    .wait_effect_checkpoint_with_operations(
      request,
      allowed,
      persisted,
      before.revision,
      {
        authorization_context_cid: "sha256:" + "a".repeat(64),
        environment_binding_cid: "sha256:" + "b".repeat(64),
      },
      [],
      "2026-10-10T00:00:30.000Z",
      () => true,
      operations=Some(access),
    )
    .unwrap()
  let key = @host.client_request_scope_cid(request)
  assert_eq(waiting.revision, before.revision + 1L)
  assert_true(calls.contains("begin"))
  assert_true(calls.contains("commit"))
  assert_true(calls.contains("read:client_runs:" + key))
  assert_true(calls.contains("insert:client_effect_custody:" + key))
  assert_true(calls.contains("compare_exchange:client_runs:" + key))
  assert_eq(
    native_client_run_checkpoint_state(waiting).unwrap().status,
    @publication.WaitingCheckpoint,
  )
  calls.clear()
  let refused = journal.wait_effect_checkpoint_with_operations(
    request,
    allowed,
    persisted,
    waiting.revision,
    {
      authorization_context_cid: "sha256:" + "a".repeat(64),
      environment_binding_cid: "sha256:" + "b".repeat(64),
    },
    [],
    "2026-10-10T00:00:31.000Z",
    () => false,
    operations=Some(access),
  )
  assert_true(refused is Err(AuthorizationDenied))
  assert_eq(calls.length(), 0)
  database.close_checked().unwrap()
}
