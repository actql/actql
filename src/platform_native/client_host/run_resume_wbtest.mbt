///|
fn resume_test_binding() -> @checkpoint.ResumeBinding {
  {
    authorization_context_cid: "sha256:" + "a".repeat(64),
    environment_binding_cid: "sha256:" + "b".repeat(64),
  }
}

///|
fn resume_test_claim(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  claimant : String,
  at : Int64,
  lease : Int64,
  binding : @checkpoint.ResumeBinding,
  current : () -> Bool,
  before_commit? : () -> Unit = () => (),
  installed? : Bool = true,
  resolution_mode? : String = "APPROVE",
) -> Result[NativeClientEffectResumeAction, NativeClientRunJournalIssue] {
  let wire = @env.get_env_var(
    "ACTQL_TEST_CLIENT_" + resolution_mode + "_RESOLUTION_WIRE",
  ).unwrap()
  journal.claim_effect_resume(
    request,
    epoch_test_crypto(),
    {
      key_id: "reviewer-key",
      reviewer_id: "native-reviewer",
      expected_authority_scope_cid: "sha256:" + "5".repeat(64),
      authority_context_cid: "sha256:" + "6".repeat(64),
      policy_cid: "sha256:" + "7".repeat(64),
      proof_preimage: @checkpoint.resolution_proof_preimage(
        wire,
        native_checkpoint_limits(),
      ).unwrap(),
    },
    [{ key_id: "reviewer-key", reviewer_id: "native-reviewer", }],
    if installed {
      [
        {
          key_id: "host-key",
          public_key_pem: @env.get_env_var("ACTQL_TEST_CLIENT_HOST_PUBLIC_KEY").unwrap(),
        },
      ]
    } else {
      []
    },
    claimant,
    lease,
    binding,
    current,
    () => {
      before_commit()
      ("2026-10-10T00:03:00.000Z", at)
    },
  )
}

///|
fn resume_test_approved(
  database : @sqlite.Database,
) -> (
  NativeClientRunJournal,
  @host.ClientRequestIdentity,
  NativeClientRunRecord,
) raise {
  let (journal, request, _) = checkpoint_test_waiting(database, [])
  let record = checkpoint_test_resolve(
    journal,
    request,
    "APPROVE",
    () => true,
    () => "2026-10-10T00:02:00.000Z",
  ).unwrap()
  assert_eq(record.checkpoint.unwrap().resume_intent.unwrap(), {
    state: @checkpoint.ResumePending,
    generation: 0L,
    claimant: "",
    lease_expires_ms: 0L,
  })
  (journal, request, record)
}

///|
test "Native original resume lease survives reopen and fences an expired generation" {
  let database = epoch_test_database("client-resume-reopen")
  let (journal, request, approved) = resume_test_approved(database)
  guard resume_test_claim(
      journal,
      request,
      "host-first",
      1000L,
      100L,
      resume_test_binding(),
      () => true,
    )
    is Ok(Claimed(first)) else {
    fail("claim missing")
  }
  assert_eq(first.claim.generation, 1L)
  assert_true(
    journal.effect_resume_fence(first, () => true, () => 1099L) is Ok(Current),
  )
  assert_true(
    resume_test_claim(
      journal,
      request,
      "host-second",
      1099L,
      100L,
      resume_test_binding(),
      () => true,
    )
    is Ok(Busy),
  )
  guard journal.lookup(request, true) is Ok(Retained(claimed)) else {
    fail("original Run missing")
  }
  assert_eq(claimed.revision, approved.revision + 1L)
  assert_eq(
    claimed.checkpoint.unwrap().resume_intent.unwrap().lease_expires_ms,
    1100L,
  )
  assert_true(
    journal.effect_resume_fence(first, () => true, () => 1100L) is Ok(Stale),
  )
  database.close_checked().unwrap()
  let reopened = epoch_test_database("client-resume-reopen")
  let journal = open_native_client_run_journal(reopened, 8).unwrap()
  assert_true(
    resume_test_claim(
      journal,
      request,
      "host-second",
      1099L,
      100L,
      resume_test_binding(),
      () => true,
    )
    is Ok(Busy),
  )
  guard resume_test_claim(
      journal,
      request,
      "host-second",
      1100L,
      100L,
      resume_test_binding(),
      () => true,
    )
    is Ok(Claimed(second)) else {
    fail("takeover missing")
  }
  assert_eq(second.claim.generation, 2L)
  assert_true(
    journal.effect_resume_fence(first, () => true, () => 1100L) is Ok(Stale),
  )
  assert_true(
    journal.effect_resume_fence(second, () => true, () => 1100L) is Ok(Current),
  )
  assert_false(journal.claim_physical_start(request, true).unwrap())
  guard journal.lookup(request, true) is Ok(Retained(restored)) else {
    fail("Run missing")
  }
  assert_eq(
    native_client_run_checkpoint_state(restored).unwrap().run_id,
    "checkpoint-run",
  )
  assert_eq(
    native_client_run_checkpoint_state(restored).unwrap().status,
    @publication.Resuming,
  )
  reopened.close_checked().unwrap()
}

///|
test "Native resume requires original approval and current installed authority" {
  let database = epoch_test_database("client-resume-authority")
  let (journal, request, _) = checkpoint_test_waiting(database, [])
  assert_true(
    resume_test_claim(
      journal,
      request,
      "host",
      1000L,
      100L,
      resume_test_binding(),
      () => true,
    )
    is Err(Checkpoint(NeedsOriginalContinuation)),
  )
  let approved = checkpoint_test_resolve(
    journal,
    request,
    "APPROVE",
    () => true,
    () => "2026-10-10T00:02:00.000Z",
  ).unwrap()
  assert_true(
    resume_test_claim(
      journal,
      request,
      "host",
      1000L,
      100L,
      resume_test_binding(),
      () => false,
    )
    is Err(AuthorizationDenied),
  )
  assert_true(
    resume_test_claim(
      journal,
      request,
      "host",
      1000L,
      100L,
      resume_test_binding(),
      () => true,
      installed=false,
    )
    is Err(Checkpoint(Signature(_))),
  )
  let calls = Ref(0)
  assert_true(
    resume_test_claim(
      journal,
      request,
      "host",
      1000L,
      100L,
      resume_test_binding(),
      () => {
        calls.val += 1
        calls.val < 4
      },
    )
    is Err(AuthorizationDenied),
  )
  guard journal.lookup(request, true) is Ok(Retained(after)) else {
    fail("Run missing")
  }
  assert_eq(after.revision, approved.revision)
  assert_eq(
    after.checkpoint.unwrap().resume_intent.unwrap().state,
    @checkpoint.ResumePending,
  )
  database.close_checked().unwrap()
}

///|
test "Native resume uses common claimant clock lease and binding validation" {
  let database = epoch_test_database("client-resume-invalid-material")
  let (journal, request, approved) = resume_test_approved(database)
  for
    (claimant, at, lease) in [
      ("", 1000L, 100L),
      ("host", -1L, 100L),
      ("host", 1000L, 0L),
      ("host", 1000L, 86400001L),
      ("host", 9007199254740991L, 1L),
    ] {
    assert_true(
      resume_test_claim(
        journal,
        request,
        claimant,
        at,
        lease,
        resume_test_binding(),
        () => true,
      )
      is Err(Checkpoint(Resume(_))),
    )
  }
  assert_true(
    resume_test_claim(
      journal,
      request,
      "host",
      1000L,
      100L,
      { ..resume_test_binding(), environment_binding_cid: "not-a-cid", },
      () => true,
    )
    is Err(Checkpoint(Resume(InvalidBinding))),
  )
  guard journal.lookup(request, true) is Ok(Retained(after)) else {
    fail("Run missing")
  }
  assert_eq(after.revision, approved.revision)
  database.close_checked().unwrap()
}

///|
test "Native changed binding retains a sticky settlement-only generation" {
  let database = epoch_test_database("client-resume-settlement")
  let (journal, request, _) = resume_test_approved(database)
  guard resume_test_claim(
      journal,
      request,
      "host-first",
      1000L,
      100L,
      {
        ..resume_test_binding(),
        environment_binding_cid: "sha256:" + "c".repeat(64),
      },
      () => true,
    )
    is Ok(SettlementOnly(first)) else {
    fail("settlement missing")
  }
  assert_true(
    journal.effect_resume_fence(first, () => true, () => 1001L)
    is Ok(SettlementOnly),
  )
  database.close_checked().unwrap()
  let reopened = epoch_test_database("client-resume-settlement")
  let journal = open_native_client_run_journal(reopened, 8).unwrap()
  guard resume_test_claim(
      journal,
      request,
      "host-second",
      1100L,
      100L,
      resume_test_binding(),
      () => true,
    )
    is Ok(SettlementOnly(second)) else {
    fail("sticky settlement lost")
  }
  assert_eq(second.claim.generation, 2L)
  guard journal.lookup(request, true) is Ok(Retained(after)) else {
    fail("Run missing")
  }
  assert_true(after.checkpoint.unwrap().settlement_only)
  assert_eq(after.checkpoint.unwrap().state.status, @publication.Resuming)
  reopened.close_checked().unwrap()
}

///|
test "Native cancellation fences sending without erasing resume observation responsibility" {
  let database = epoch_test_database("client-resume-cancel-fence")
  let (journal, request, _) = resume_test_approved(database)
  guard resume_test_claim(
      journal,
      request,
      "host-first",
      1000L,
      100L,
      resume_test_binding(),
      () => true,
    )
    is Ok(Claimed(first)) else {
    fail("claim missing")
  }
  guard journal.lookup(request, true) is Ok(Retained(record)) else {
    fail("Run missing")
  }
  journal
  .transaction(() => journal.save({ ..record, cancellation_requested: true, }))
  .unwrap()
  |> ignore
  assert_true(
    journal.effect_resume_fence(first, () => true, () => 1001L)
    is Ok(SettlementOnly),
  )
  guard resume_test_claim(
      journal,
      request,
      "host-second",
      1100L,
      100L,
      resume_test_binding(),
      () => true,
    )
    is Ok(SettlementOnly(second)) else {
    fail("cancel settlement missing")
  }
  assert_true(
    journal.effect_resume_fence(second, () => false, () => 1101L)
    is Err(AuthorizationDenied),
  )
  assert_true(
    journal.effect_resume_fence(second, () => true, () => -1L)
    is Err(Checkpoint(Resume(InvalidClock))),
  )
  guard journal.lookup(request, true) is Ok(Retained(after)) else {
    fail("Run missing")
  }
  assert_eq(after.checkpoint.unwrap().state.status, @publication.Resuming)
  assert_true(after.cancellation_requested)
  database.close_checked().unwrap()
}

///|
test "Native resume admission cannot overwrite an intervening cancellation revision" {
  let database = epoch_test_database("client-resume-revision-race")
  let (journal, request, approved) = resume_test_approved(database)
  assert_true(
    resume_test_claim(
      journal,
      request,
      "host",
      1000L,
      100L,
      resume_test_binding(),
      () => true,
      before_commit=() => {
        journal
        .transaction(() => {
          journal.save({ ..approved, cancellation_requested: true, })
        })
        .unwrap()
        |> ignore
      },
    )
    is Err(Checkpoint(StaleRevision)),
  )
  guard journal.lookup(request, true) is Ok(Retained(after)) else {
    fail("Run missing")
  }
  assert_eq(after.revision, approved.revision + 1L)
  assert_true(after.cancellation_requested)
  assert_eq(
    after.checkpoint.unwrap().resume_intent.unwrap().state,
    @checkpoint.ResumePending,
  )
  database.close_checked().unwrap()
}

///|
test "Native original resume claim distinguishes precommit failure and lost commit reply" {
  for reply_lost in [false, true] {
    let name = "client-resume-commit-loss-" + reply_lost.to_string()
    let database = epoch_test_database(name)
    let (journal, request, approved) = resume_test_approved(database)
    assert_true(
      resume_test_claim(
        journal,
        request,
        "host-first",
        1000L,
        100L,
        resume_test_binding(),
        () => true,
        before_commit=() => {
          if reply_lost {
            client_test_fail_commit_reply(database, 1)
          } else {
            client_test_fail_commit(database, 1)
          }
        },
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
    guard journal.lookup(request, true) is Ok(Retained(after)) else {
      fail("original Run missing")
    }
    assert_eq(
      after.revision,
      approved.revision + (if reply_lost { 1L } else { 0L }),
    )
    assert_eq(
      after.checkpoint.unwrap().resume_intent.unwrap().state,
      if reply_lost {
        @checkpoint.ResumeClaimed
      } else {
        @checkpoint.ResumePending
      },
    )
    if reply_lost {
      assert_true(
        resume_test_claim(
          journal,
          request,
          "host-second",
          1099L,
          100L,
          resume_test_binding(),
          () => true,
        )
        is Ok(Busy),
      )
    } else {
      assert_true(
        resume_test_claim(
          journal,
          request,
          "host-second",
          1099L,
          100L,
          resume_test_binding(),
          () => true,
        )
        is Ok(Claimed(_)),
      )
    }
    reopened.close_checked().unwrap()
  }
}

///|
test "Native resume custody rejects missing inconsistent or noncanonical retained claims" {
  let database = epoch_test_database("client-resume-corrupt")
  let (_, _, approved) = resume_test_approved(database)
  let checkpoint = approved.checkpoint.unwrap()
  let invalid_intents : Array[@checkpoint.ResumeIntentView] = [
    {
      state: @checkpoint.ResumePending,
      generation: 1L,
      claimant: "",
      lease_expires_ms: 0L,
    },
    {
      state: @checkpoint.ResumeClaimed,
      generation: 1L,
      claimant: "",
      lease_expires_ms: 1100L,
    },
    {
      state: @checkpoint.ResumeClaimed,
      generation: 1L,
      claimant: "host",
      lease_expires_ms: -1L,
    },
    {
      state: @checkpoint.ResumeCompleted,
      generation: 1L,
      claimant: "host",
      lease_expires_ms: 1100L,
    },
  ]
  for intent in invalid_intents {
    let wire = checkpoint_record_body({
      ..checkpoint,
      resume_intent: Some(intent),
    }).unwrap()
    assert_true(
      read_checkpoint_record(wire, approved.definition) is Err(InvalidMaterial),
    )
  }
  for
    corrupt in [
      { ..checkpoint, resume_intent: None, },
      { ..checkpoint, settlement_only: true, },
    ] {
    assert_true(
      read_checkpoint_record(
        checkpoint_record_body(corrupt).unwrap(),
        approved.definition,
      )
      is Err(InvalidMaterial),
    )
  }
  let wire = checkpoint_resume_body({
    state: @checkpoint.ResumeClaimed,
    generation: 1L,
    claimant: "host",
    lease_expires_ms: 1100L,
  })
  assert_eq(
    read_checkpoint_resume(
      wire.replace_all(old="\"generation\":\"1\"", new="\"generation\":\"01\""),
      resume_test_binding(),
    ),
    None,
  )
  database.close_checked().unwrap()
}
