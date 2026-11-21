///|
fn checkpoint_test_artifact(
  definition : @publication.PublicationContract,
) -> @checkpoint.SealedCheckpoint {
  @checkpoint.seal_checkpoint(
    {
      checkpoint_id: "client-original-checkpoint",
      continuation_state_cid: "sha256:" + "2".repeat(64),
      subject: RunUnit(
        run_id="checkpoint-run",
        unit_id="unit-1",
        run_definition_cid=@publication.publication_contract_identity(
          definition,
        ),
      ),
      phase: Commit,
      kind: EffectSet,
      required_artifact_cid: "sha256:" + "3".repeat(64),
      review_projection_cid: "sha256:" + "4".repeat(64),
      requirements: [EffectScopeApproved, PartialApplicationAccepted],
      reason_code: "effect_review_required",
      human_summary: "Review original Effect",
      created_at: "2026-10-10T00:00:00.000Z",
      expires_at: "2026-10-11T00:00:00.000Z",
    },
    native_checkpoint_limits(),
  ).unwrap()
}

///|
// The signing fixture takes original references, never expected Run status
// or results, from this compilation. Independent Node keys sign the existing
// protocol; assertions below independently require waiting/resuming/refusal.
test "export original Native Client Checkpoint signing references" {
  let (_, _, _, definition) = journal_test_run(
    "checkpoint-request", "checkpoint-run",
  )
  println(
    "ACTQL_CLIENT_CHECKPOINT " + checkpoint_test_artifact(definition).wire,
  )
}

///|
fn checkpoint_test_waiting(
  database : @sqlite.Database,
  unknown_effects : Array[String],
) -> (
  NativeClientRunJournal,
  @host.ClientRequestIdentity,
  NativeClientRunRecord,
) raise {
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "checkpoint-request", "checkpoint-run",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  journal.reserve_dispatch(request, true).unwrap() |> ignore
  assert_true(journal.claim_physical_start(request, true).unwrap())
  guard journal.lookup(request, true) is Ok(Retained(before)) else {
    fail("original Run missing")
  }
  let artifact = checkpoint_test_artifact(definition)
  // This transaction fixture confirms its explicit durable artifact through
  // the shared persistence law. It is not Native Effect preview acceptance.
  database
  .insert(
    "test_checkpoint_artifacts",
    artifact.checkpoint_cid,
    @utf8.encode(artifact.wire),
  )
  .unwrap()
  |> ignore
  let physical = @utf8.decode(
    database.read("test_checkpoint_artifacts", artifact.checkpoint_cid).unwrap().body,
  )
  let persisted = @checkpoint.confirm_checkpoint_persisted(artifact, physical).unwrap()
  let waiting = journal
    .wait_checkpoint(
      request,
      compiled,
      persisted,
      before.revision,
      {
        authorization_context_cid: "sha256:" + "a".repeat(64),
        environment_binding_cid: "sha256:" + "b".repeat(64),
      },
      unknown_effects,
      "2026-10-10T00:00:30.000Z",
      () => true,
    )
    .unwrap()
  assert_eq(
    native_client_run_checkpoint_state(waiting).unwrap().status,
    @publication.WaitingCheckpoint,
  )
  assert_eq(
    native_client_run_checkpoint_state(waiting).unwrap().run_id,
    "checkpoint-run",
  )
  assert_eq(waiting.checkpoint.unwrap().declared_results, ["answer"])
  (journal, request, waiting)
}

///|
fn checkpoint_test_resolve(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  mode : String,
  current : () -> Bool,
  now : () -> String,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  let prefix = "ACTQL_TEST_CLIENT_" + mode + "_"
  let resolution_wire = @env.get_env_var(prefix + "RESOLUTION_WIRE").unwrap()
  let verified_wire = @env.get_env_var(prefix + "VERIFIED_WIRE").unwrap()
  journal.resolve_effect_checkpoint(
    request,
    epoch_test_crypto(),
    verified_wire,
    {
      key_id: "reviewer-key",
      reviewer_id: "native-reviewer",
      expected_authority_scope_cid: "sha256:" + "5".repeat(64),
      authority_context_cid: "sha256:" + "6".repeat(64),
      policy_cid: "sha256:" + "7".repeat(64),
      proof_preimage: @checkpoint.resolution_proof_preimage(
        resolution_wire,
        native_checkpoint_limits(),
      ).unwrap(),
    },
    [{ key_id: "reviewer-key", reviewer_id: "native-reviewer", }],
    [
      {
        key_id: "host-key",
        public_key_pem: @env.get_env_var("ACTQL_TEST_CLIENT_HOST_PUBLIC_KEY").unwrap(),
      },
    ],
    current,
    now,
  )
}

///|
test "Native original Checkpoint approval is durable and never repeats physical start" {
  let database = epoch_test_database("client-checkpoint-approval")
  let (journal, request, waiting) = checkpoint_test_waiting(database, [])
  assert_true(
    checkpoint_test_resolve(journal, request, "APPROVE", () => false, () => {
      "2026-10-10T00:02:00.000Z"
    })
    is Err(AuthorizationDenied),
  )
  let approved = checkpoint_test_resolve(
    journal,
    request,
    "APPROVE",
    () => true,
    () => "2026-10-10T00:02:00.000Z",
  ).unwrap()
  assert_eq(approved.revision, waiting.revision + 1L)
  assert_eq(approved.checkpoint.unwrap().state.status, @publication.Resuming)
  assert_true(approved.checkpoint.unwrap().resume_intent_id is Some(_))
  database.close_checked().unwrap()
  let reopened = epoch_test_database("client-checkpoint-approval")
  let journal = open_native_client_run_journal(reopened, 8).unwrap()
  guard journal.lookup(request, true) is Ok(Retained(restored)) else {
    fail("original approval missing")
  }
  assert_eq(restored.revision, approved.revision)
  assert_eq(
    restored.checkpoint.unwrap().state.wire,
    approved.checkpoint.unwrap().state.wire,
  )
  assert_eq(
    restored.checkpoint.unwrap().resume_intent_id,
    approved.checkpoint.unwrap().resume_intent_id,
  )
  assert_false(journal.claim_physical_start(request, true).unwrap())
  let duplicate = checkpoint_test_resolve(
    journal,
    request,
    "APPROVE",
    () => true,
    () => "2026-10-12T00:00:00.000Z",
  ).unwrap()
  assert_eq(duplicate.revision, approved.revision)
  assert_true(
    checkpoint_test_resolve(journal, request, "CONFLICT", () => true, () => {
      "2026-10-10T00:03:00.000Z"
    })
    is Err(Checkpoint(ConflictingResolution)),
  )
  reopened.close_checked().unwrap()
}

///|
test "Native Checkpoint rejection preserves unresolved Effect responsibility" {
  for unknown in [false, true] {
    let database = epoch_test_database(
      "client-checkpoint-reject-" + unknown.to_string(),
    )
    let (journal, request, _) = checkpoint_test_waiting(
      database,
      if unknown {
        ["effect-original"]
      } else {
        []
      },
    )
    let rejected = checkpoint_test_resolve(
      journal,
      request,
      "REJECT",
      () => true,
      () => "2026-10-10T00:02:00.000Z",
    ).unwrap()
    assert_eq(
      rejected.checkpoint.unwrap().state.status,
      if unknown {
        @publication.NeedsReconciliation
      } else {
        @publication.Cancelled
      },
    )
    assert_eq(rejected.checkpoint.unwrap().resume_intent_id, None)
    database.close_checked().unwrap()
    let reopened = epoch_test_database(
      "client-checkpoint-reject-" + unknown.to_string(),
    )
    let journal = open_native_client_run_journal(reopened, 8).unwrap()
    guard journal.lookup(request, true) is Ok(Retained(restored)) else {
      fail("original refusal missing")
    }
    assert_eq(
      restored.checkpoint.unwrap().state.wire,
      rejected.checkpoint.unwrap().state.wire,
    )
    reopened.close_checked().unwrap()
  }
}

///|
test "Native Checkpoint current deadline and revision fence historical approval" {
  let database = epoch_test_database("client-checkpoint-fences")
  let (journal, request, waiting) = checkpoint_test_waiting(database, [])
  assert_true(
    checkpoint_test_resolve(journal, request, "APPROVE", () => true, () => {
      "2026-10-11T00:00:00.000Z"
    })
    is Err(Checkpoint(Expired)),
  )
  let changed = Ref(false)
  assert_true(
    checkpoint_test_resolve(
      journal,
      request,
      "APPROVE",
      () => {
        if !changed.val {
          changed.val = true
          // Another observer commits cancellation while signature admission is
          // outside the transaction. Its revision must not be overwritten.
          journal
          .transaction(() => {
            journal.save({ ..waiting, cancellation_requested: true, })
          })
          .unwrap()
          |> ignore
        }
        true
      },
      () => "2026-10-10T00:02:00.000Z",
    )
    is Err(Checkpoint(NeedsOriginalContinuation)),
  )
  guard journal.lookup(request, true) is Ok(Retained(after)) else {
    fail("original cancellation missing")
  }
  assert_true(after.cancellation_requested)
  assert_eq(
    after.checkpoint.unwrap().state.status,
    @publication.WaitingCheckpoint,
  )
  assert_eq(after.checkpoint.unwrap().verified_wire, None)
  database.close_checked().unwrap()
}

///|
test "Native Checkpoint signature admission cannot overwrite a concurrent revision" {
  let database = epoch_test_database("client-checkpoint-revision-race")
  let (journal, request, waiting) = checkpoint_test_waiting(database, [])
  let calls = Ref(0)
  assert_true(
    checkpoint_test_resolve(
      journal,
      request,
      "APPROVE",
      () => {
        calls.val += 1
        if calls.val == 3 {
          journal
          .transaction(() => {
            journal.save({ ..waiting, cancellation_requested: true, })
          })
          .unwrap()
          |> ignore
        }
        true
      },
      () => "2026-10-10T00:02:00.000Z",
    )
    is Err(Checkpoint(StaleRevision)),
  )
  guard journal.lookup(request, true) is Ok(Retained(after)) else {
    fail("original Run missing")
  }
  assert_eq(after.revision, waiting.revision + 1L)
  assert_true(after.cancellation_requested)
  assert_eq(
    after.checkpoint.unwrap().state.status,
    @publication.WaitingCheckpoint,
  )
  assert_eq(after.checkpoint.unwrap().verified_wire, None)
  database.close_checked().unwrap()
}

///|
test "Native Checkpoint authority lost after physical verification leaves no approval" {
  let database = epoch_test_database("client-checkpoint-authority-race")
  let (journal, request, waiting) = checkpoint_test_waiting(database, [])
  let calls = Ref(0)
  assert_true(
    checkpoint_test_resolve(
      journal,
      request,
      "APPROVE",
      () => {
        calls.val += 1
        calls.val < 4
      },
      () => "2026-10-10T00:02:00.000Z",
    )
    is Err(AuthorizationDenied),
  )
  guard journal.lookup(request, true) is Ok(Retained(after)) else {
    fail("original Run missing")
  }
  assert_eq(after.revision, waiting.revision)
  assert_eq(after.checkpoint.unwrap().verified_wire, None)
  assert_eq(after.checkpoint.unwrap().resume_intent_id, None)
  database.close_checked().unwrap()
}

///|
test "Native Checkpoint closure and resume intent survive commit reply loss together" {
  for reply_lost in [false, true] {
    let name = "client-checkpoint-commit-loss-" + reply_lost.to_string()
    let database = epoch_test_database(name)
    let (journal, request, _) = checkpoint_test_waiting(database, [])
    // The public resolver performs a read-only transaction first. Inject at
    // the final authorization callback, immediately before its write commit.
    let calls = Ref(0)
    assert_true(
      checkpoint_test_resolve(
        journal,
        request,
        "APPROVE",
        () => {
          calls.val += 1
          if calls.val == 4 {
            if reply_lost {
              client_test_fail_commit_reply(database, 1)
            } else {
              client_test_fail_commit(database, 1)
            }
          }
          true
        },
        () => "2026-10-10T00:02:00.000Z",
      )
      is Err(TransactionUnknown),
    )
    assert_true(database.transaction_fenced())
    if !reply_lost {
      database.rollback().unwrap()
    }
    database.close_checked().unwrap()
    let reopened = epoch_test_database(name)
    let journal = open_native_client_run_journal(reopened, 8).unwrap()
    guard journal.lookup(request, true) is Ok(Retained(restored)) else {
      fail("original checkpoint missing")
    }
    let checkpoint = restored.checkpoint.unwrap()
    assert_eq(
      checkpoint.state.status,
      if reply_lost {
        @publication.Resuming
      } else {
        @publication.WaitingCheckpoint
      },
    )
    assert_eq(checkpoint.resolution_cid is Some(_), reply_lost)
    assert_eq(checkpoint.verified_wire is Some(_), reply_lost)
    assert_eq(checkpoint.resume_intent_id is Some(_), reply_lost)
    assert_false(journal.claim_physical_start(request, true).unwrap())
    reopened.close_checked().unwrap()
  }
}

///|
fn checkpoint_test_resolve_with_operations(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  mode : String,
  current : () -> Bool,
  now : () -> String,
  operations : NativeClientJournalOperationAccess,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  let prefix = "ACTQL_TEST_CLIENT_" + mode + "_"
  let resolution_wire = @env.get_env_var(prefix + "RESOLUTION_WIRE").unwrap()
  let verified_wire = @env.get_env_var(prefix + "VERIFIED_WIRE").unwrap()
  journal.resolve_effect_checkpoint_with_operations(
    request,
    epoch_test_crypto(),
    verified_wire,
    {
      key_id: "reviewer-key",
      reviewer_id: "native-reviewer",
      expected_authority_scope_cid: "sha256:" + "5".repeat(64),
      authority_context_cid: "sha256:" + "6".repeat(64),
      policy_cid: "sha256:" + "7".repeat(64),
      proof_preimage: @checkpoint.resolution_proof_preimage(
        resolution_wire,
        native_checkpoint_limits(),
      ).unwrap(),
    },
    [{ key_id: "reviewer-key", reviewer_id: "native-reviewer", }],
    [
      {
        key_id: "host-key",
        public_key_pem: @env.get_env_var("ACTQL_TEST_CLIENT_HOST_PUBLIC_KEY").unwrap(),
      },
    ],
    current,
    now,
    Some(operations),
  )
}

///|
test "Checkpoint original operation access admits construction before the same durable CAS" {
  let database = epoch_test_database("checkpoint-routed-approval")
  let (journal, request, waiting) = checkpoint_test_waiting(database, [])
  let calls : Array[String] = []
  let access = {
    ..journal_test_operation_access(database, calls),
    before_construction: Some((bytes, nodes, depth) => {
      if bytes <= 0 || nodes != 32 || depth != 4 {
        return Err(@host.ClientJournalEncodingIssue::Encoding)
      }
      calls.push("construct")
      Ok(())
    }),
    compare_exchange: (table, key, revision, body) => {
      if table == "client_runs" {
        if !calls.contains("construct") {
          return Err(@sqlite.CapacityExceeded)
        }
        calls.push("run-cas")
      }
      database.compare_exchange(table, key, revision, body)
    },
  }
  let approved = checkpoint_test_resolve_with_operations(
    journal,
    request,
    "APPROVE",
    () => true,
    () => "2026-10-10T00:02:00.000Z",
    access,
  )
  let approved = match approved {
    Ok(value) => value
    Err(issue) =>
      fail("checkpoint routed commit: " + selected_policy_journal_issue(issue))
  }
  assert_eq(approved.revision, waiting.revision + 1L)
  assert_eq(approved.checkpoint.unwrap().state.status, @publication.Resuming)
  assert_true(calls.contains("construct"))
  assert_true(calls.contains("run-cas"))
  assert_eq(calls[calls.length() - 1], "commit")
  assert_false(database.transaction_fenced())
  database.close_checked().unwrap()
}

///|
test "Checkpoint constructor refusal rolls back original waiting and foreign access is rejected" {
  let database = epoch_test_database("checkpoint-routed-refusal")
  let foreign = epoch_test_database("checkpoint-routed-foreign")
  let (journal, request, waiting) = checkpoint_test_waiting(database, [])
  let calls : Array[String] = []
  let access = {
    ..journal_test_operation_access(database, calls),
    before_construction: Some((_, _, _) => {
      calls.push("construct-refused")
      Err(@host.ClientJournalEncodingIssue::CapacityExceeded)
    }),
  }
  assert_true(
    checkpoint_test_resolve_with_operations(
      journal,
      request,
      "APPROVE",
      () => true,
      () => "2026-10-10T00:02:00.000Z",
      access,
    )
    is Err(CapacityExceeded),
  )
  assert_true(calls.contains("construct-refused"))
  assert_eq(calls[calls.length() - 1], "rollback")
  assert_false(
    calls.any(value => value.has_prefix("compare_exchange:client_runs:")),
  )
  guard journal.lookup(request, true) is Ok(Retained(after)) else {
    fail("original waiting Run missing")
  }
  assert_eq(after.revision, waiting.revision)
  assert_eq(
    after.checkpoint.unwrap().state.wire,
    waiting.checkpoint.unwrap().state.wire,
  )
  assert_true(after.checkpoint.unwrap().resolution_cid is None)
  assert_false(database.transaction_fenced())
  let foreign_calls : Array[String] = []
  assert_true(
    checkpoint_test_resolve_with_operations(
      journal,
      request,
      "APPROVE",
      () => true,
      () => "2026-10-10T00:02:00.000Z",
      journal_test_operation_access(foreign, foreign_calls),
    )
    is Err(CustodyLost),
  )
  assert_eq(foreign_calls.length(), 0)
  assert_true(
    checkpoint_test_resolve_with_operations(
      journal,
      request,
      "APPROVE",
      () => false,
      () => "2026-10-10T00:02:00.000Z",
      access,
    )
    is Err(AuthorizationDenied),
  )
  database.close_checked().unwrap()
  foreign.close_checked().unwrap()
}

///|
test "Checkpoint original operation lost COMMIT remains Unknown and fences further resolution" {
  let database = epoch_test_database("checkpoint-routed-lost-commit")
  let (journal, request, waiting) = checkpoint_test_waiting(database, [])
  let calls : Array[String] = []
  let ordinary = journal_test_read_access(database, calls)
  let reads = {
    ..ordinary,
    transaction: operation => {
      if operation is JournalCommit && calls.contains("resolution-cas") {
        database.commit().unwrap()
        calls.push("commit-reply-lost")
        Err(@sqlite.Busy)
      } else {
        (ordinary.transaction)(operation)
      }
    },
  }
  let access = {
    ..journal_test_operation_access(database, calls),
    reads,
    before_construction: Some((_, _, _) => Ok(())),
    compare_exchange: (table, key, revision, body) => {
      if table == "client_runs" {
        calls.push("resolution-cas")
      }
      database.compare_exchange(table, key, revision, body)
    },
  }
  assert_true(
    checkpoint_test_resolve_with_operations(
      journal,
      request,
      "APPROVE",
      () => true,
      () => "2026-10-10T00:02:00.000Z",
      access,
    )
    is Err(TransactionUnknown),
  )
  assert_true(calls.contains("commit-reply-lost"))
  assert_true(journal.fenced)
  assert_true(database.transaction_fenced())
  assert_true(journal.admitted_record is None)
  let row = database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap()
  let retained = read_run_record(row).unwrap()
  assert_eq(retained.revision, waiting.revision + 1L)
  assert_eq(retained.checkpoint.unwrap().state.status, @publication.Resuming)
  let before = calls.length()
  assert_true(
    checkpoint_test_resolve_with_operations(
      journal,
      request,
      "APPROVE",
      () => true,
      () => "2026-10-10T00:02:00.000Z",
      access,
    )
    is Err(Fenced),
  )
  assert_eq(calls.length(), before)
  database.close_checked().unwrap()
}
