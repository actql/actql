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
