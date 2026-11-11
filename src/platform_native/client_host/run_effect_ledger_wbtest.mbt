///|
fn effect_row_test_binding(
  request : @host.ClientRequestIdentity,
  row? : String = "row-1",
  preview? : String = "sha256:" + "3".repeat(64),
) -> (
  @effect.LogicalItemLocator,
  @effect.EffectDispatchKey,
  @effect.EffectLedgerBasis,
) {
  let scope = @host.client_request_logical_scope(request)
  let locator = @effect.prepare_logical_item_locator(
    scope,
    "original-program",
    "original-stage",
    "WriteOne",
    "\"" + row + "\"",
    64,
    128,
    16,
    4,
  ).unwrap()
  let key = @effect.prepare_effect_dispatch_key(
    scope,
    preview,
    "\"" + row + "\"",
    128,
    16,
    4,
  ).unwrap()
  let basis = @effect.prepare_effect_ledger_basis(
    scope,
    locator,
    key,
    "sha256:" + "c".repeat(64),
    "sha256:" + "d".repeat(64),
    "sha256:" + "e".repeat(64),
    "sha256:" + "f".repeat(64),
    "sha256:" + "0".repeat(64),
    "unavailable",
    "sha256:" + "1".repeat(64),
    "sha256:" + "2".repeat(64),
  ).unwrap()
  (locator, key, basis)
}

///|
fn effect_row_test_claim(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  claimant? : String = "host-first",
  at? : Int64 = 1000L,
) -> NativeClientEffectResumeClaim raise {
  guard resume_test_claim(
      journal,
      request,
      claimant,
      at,
      100L,
      resume_test_binding(),
      () => true,
    )
    is Ok(Claimed(claim)) else {
    fail("original resume claim missing")
  }
  claim
}

///|
test "Native row dispatch custody is atomic and repeated claims never dispatch again" {
  let database = epoch_test_database("client-row-dispatch")
  let (journal, request, _) = resume_test_approved(database)
  let claim = effect_row_test_claim(journal, request)
  let (locator, key, basis) = effect_row_test_binding(request)
  guard journal.record_effect_row_dispatch(
      claim,
      locator,
      key,
      basis,
      () => true,
      () => 1001L,
    )
    is Ok(DispatchRecorded(dispatch)) else {
    fail("original dispatch missing")
  }
  assert_eq(@effect.effect_ledger_entry_state_code(dispatch.dispatching), 1)
  guard journal.lookup(request, true) is Ok(Retained(before)) else {
    fail("Run missing")
  }
  let history = before.checkpoint.unwrap().effect_ledger
  assert_eq(history.length(), 2)
  assert_eq(@effect.effect_ledger_entry_state_code(history[0]), 0)
  assert_true(@effect.effect_ledger_entry_follows(None, history[0]))
  assert_true(@effect.effect_ledger_entry_follows(Some(history[0]), history[1]))
  guard journal.record_effect_row_dispatch(
      claim,
      locator,
      key,
      basis,
      () => true,
      () => 1002L,
    )
    is Ok(OriginalRowRetained(prior)) else {
    fail("duplicate was dispatched")
  }
  assert_eq(
    @effect.effect_ledger_entry_cid(prior),
    @effect.effect_ledger_entry_cid(dispatch.dispatching),
  )
  guard journal.lookup(request, true) is Ok(Retained(after)) else {
    fail("Run missing")
  }
  assert_eq(after.revision, before.revision)
  assert_false(journal.claim_physical_start(request, true).unwrap())
  database.close_checked().unwrap()
}

///|
test "Native lease takeover restores original possibly-sent row rather than issuing another attempt" {
  let database = epoch_test_database("client-row-takeover")
  let (journal, request, _) = resume_test_approved(database)
  let first = effect_row_test_claim(journal, request)
  let (locator, key, basis) = effect_row_test_binding(request)
  guard journal.record_effect_row_dispatch(
      first,
      locator,
      key,
      basis,
      () => true,
      () => 1001L,
    )
    is Ok(DispatchRecorded(dispatch)) else {
    fail("dispatch missing")
  }
  let original_cid = @effect.effect_ledger_entry_cid(dispatch.dispatching)
  database.close_checked().unwrap()
  let reopened = epoch_test_database("client-row-takeover")
  let journal = open_native_client_run_journal(reopened, 8).unwrap()
  let second = effect_row_test_claim(
    journal,
    request,
    claimant="host-second",
    at=1100L,
  )
  guard journal.record_effect_row_dispatch(
      second,
      locator,
      key,
      basis,
      () => true,
      () => 1101L,
    )
    is Ok(OriginalRowRetained(original)) else {
    fail("takeover dispatched a possibly-sent row")
  }
  assert_eq(@effect.effect_ledger_entry_cid(original), original_cid)
  assert_eq(original.attempt_sequence, 1L)
  assert_eq(
    @effect.effect_row_recovery_action_from_entry(
      locator,
      basis.intent_fingerprint_cid,
      key,
      basis.canonical_request_cid,
      Some(original),
      false,
    ),
    3,
  )
  assert_true(
    journal.lookup_effect_row(request, locator, () => false)
    is Err(AuthorizationDenied),
  )
  assert_true(
    journal.lookup_effect_row(request, locator, () => true) is Ok(Some(_)),
  )
  reopened.close_checked().unwrap()
}

///|
test "Native unknown observation remains durable and idempotent after cancellation and lease expiry" {
  let database = epoch_test_database("client-row-unknown")
  let (journal, request, _) = resume_test_approved(database)
  let claim = effect_row_test_claim(journal, request)
  let (locator, key, basis) = effect_row_test_binding(request)
  guard journal.record_effect_row_dispatch(
      claim,
      locator,
      key,
      basis,
      () => true,
      () => 1001L,
    )
    is Ok(DispatchRecorded(dispatch)) else {
    fail("dispatch missing")
  }
  guard journal.lookup(request, true) is Ok(Retained(before)) else {
    fail("Run missing")
  }
  journal
  .transaction(() => journal.save({ ..before, cancellation_requested: true, }))
  .unwrap()
  |> ignore
  assert_true(
    journal.effect_resume_fence(claim, () => true, () => 1100L) is Ok(Stale),
  )
  let unknown = journal.record_effect_row_unknown(dispatch).unwrap()
  assert_eq(@effect.effect_ledger_entry_state_code(unknown), 5)
  assert_eq(unknown.attempt_sequence, 1L)
  guard journal.lookup(request, true) is Ok(Retained(observed)) else {
    fail("Run missing")
  }
  journal.record_effect_row_unknown(dispatch).unwrap() |> ignore
  guard journal.lookup(request, true) is Ok(Retained(again)) else {
    fail("Run missing")
  }
  assert_eq(again.revision, observed.revision)
  assert_true(again.cancellation_requested)
  assert_eq(again.checkpoint.unwrap().effect_ledger.length(), 3)
  database.close_checked().unwrap()
  let reopened = epoch_test_database("client-row-unknown")
  let journal = open_native_client_run_journal(reopened, 8).unwrap()
  guard journal.lookup_effect_row(request, locator, () => true)
    is Ok(Some(restored)) else {
    fail("unknown missing")
  }
  assert_eq(
    @effect.effect_ledger_entry_cid(restored),
    @effect.effect_ledger_entry_cid(unknown),
  )
  assert_eq(
    @effect.effect_row_recovery_action_from_entry(
      locator,
      basis.intent_fingerprint_cid,
      key,
      basis.canonical_request_cid,
      Some(restored),
      false,
    ),
    4,
  )
  assert_true(
    journal.record_effect_row_unknown(dispatch)
    is Err(Checkpoint(InvalidMaterial)),
  )
  guard journal.restore_effect_row_observation(request, locator, () => true)
    is Ok(Some(observation)) else {
    fail("original observation custody missing")
  }
  assert_eq(
    @effect.effect_ledger_entry_cid(observation.dispatching),
    @effect.effect_ledger_entry_cid(dispatch.dispatching),
  )
  guard journal.lookup(request, true) is Ok(Retained(before_retry)) else {
    fail("Run missing")
  }
  let repeated = journal.record_effect_row_unknown(observation).unwrap()
  assert_eq(repeated.cid, restored.cid)
  guard journal.lookup(request, true) is Ok(Retained(after_retry)) else {
    fail("Run missing")
  }
  assert_eq(after_retry.revision, before_retry.revision)
  assert_true(after_retry.cancellation_requested)
  reopened.close_checked().unwrap()
}

///|
test "Native reopened original dispatch restores observation without approval or a new send" {
  let database = epoch_test_database("client-row-observation-reopen")
  let (journal, request, _) = resume_test_approved(database)
  let claim = effect_row_test_claim(journal, request)
  let (locator, key, basis) = effect_row_test_binding(request)
  assert_true(
    journal.restore_effect_row_observation(request, locator, () => true)
    is Ok(None),
  )
  guard journal.record_effect_row_dispatch(
      claim,
      locator,
      key,
      basis,
      () => true,
      () => 1001L,
    )
    is Ok(DispatchRecorded(sent)) else {
    fail("original dispatch missing")
  }
  let original_cid = sent.dispatching.cid
  database.close_checked().unwrap()
  let reopened = epoch_test_database("client-row-observation-reopen")
  let journal = open_native_client_run_journal(reopened, 8).unwrap()
  assert_true(
    journal.restore_effect_row_observation(request, locator, () => false)
    is Err(AuthorizationDenied),
  )
  let (other, _, _, _) = journal_test_run("other-request", "other-run")
  let (foreign, _, _) = effect_row_test_binding(other)
  assert_true(
    journal.restore_effect_row_observation(request, foreign, () => true)
    is Err(Checkpoint(InvalidMaterial)),
  )
  assert_true(
    journal.restore_effect_row_observation(other, foreign, () => true)
    is Err(CustodyLost),
  )
  guard journal.lookup(request, true) is Ok(Retained(before)) else {
    fail("Run missing")
  }
  guard journal.restore_effect_row_observation(request, locator, () => true)
    is Ok(Some(observation)) else {
    fail("original observation custody missing")
  }
  assert_eq(observation.dispatching.cid, original_cid)
  assert_eq(observation.dispatching.attempt_sequence, 1L)
  guard journal.lookup(request, true) is Ok(Retained(after)) else {
    fail("Run missing")
  }
  assert_eq(after.revision, before.revision)
  assert_eq(after.checkpoint.unwrap().effect_ledger.length(), 2)
  assert_false(journal.claim_physical_start(request, true).unwrap())
  let unknown = journal.record_effect_row_unknown(observation).unwrap()
  assert_eq(@effect.effect_ledger_entry_state_code(unknown), 5)
  assert_eq(unknown.attempt_sequence, 1L)
  assert_eq(unknown.prior_entry_cid, Some(original_cid))
  reopened.close_checked().unwrap()
}

///|
test "Native row claim checks current resume fence Preview and original logical request" {
  let database = epoch_test_database("client-row-refusals")
  let (journal, request, _) = resume_test_approved(database)
  let claim = effect_row_test_claim(journal, request)
  let (locator, key, basis) = effect_row_test_binding(request)
  assert_true(
    journal.record_effect_row_dispatch(
      claim,
      locator,
      key,
      basis,
      () => false,
      () => 1001L,
    )
    is Err(AuthorizationDenied),
  )
  assert_true(
    journal.record_effect_row_dispatch(claim, locator, key, basis, () => true, () => {
      1100L
    })
    is Err(Checkpoint(StaleRevision)),
  )
  let (other_locator, other_key, other_basis) = effect_row_test_binding(
    request,
    preview="sha256:" + "4".repeat(64),
  )
  assert_true(
    journal.record_effect_row_dispatch(
      claim,
      other_locator,
      other_key,
      other_basis,
      () => true,
      () => 1001L,
    )
    is Err(Checkpoint(InvalidMaterial)),
  )
  let (foreign, _, _, _) = journal_test_run("foreign-request", "foreign-run")
  let (foreign_locator, foreign_key, foreign_basis) = effect_row_test_binding(
    foreign,
  )
  assert_true(
    journal.record_effect_row_dispatch(
      claim,
      foreign_locator,
      foreign_key,
      foreign_basis,
      () => true,
      () => 1001L,
    )
    is Err(Checkpoint(InvalidMaterial)),
  )
  assert_true(
    journal.lookup_effect_row(request, foreign_locator, () => true)
    is Err(Checkpoint(InvalidMaterial)),
  )
  guard journal.lookup(request, true) is Ok(Retained(before)) else {
    fail("Run missing")
  }
  assert_eq(before.checkpoint.unwrap().effect_ledger.length(), 0)
  assert_true(
    journal.record_effect_row_dispatch(claim, locator, key, basis, () => true, () => {
      journal
      .transaction(() => {
        journal.save({ ..before, cancellation_requested: true, })
      })
      .unwrap()
      |> ignore
      1001L
    })
    is Ok(NoSend),
  )
  guard journal.lookup(request, true) is Ok(Retained(after)) else {
    fail("Run missing")
  }
  assert_eq(after.revision, before.revision + 1L)
  assert_eq(after.checkpoint.unwrap().effect_ledger.length(), 0)
  database.close_checked().unwrap()
}

///|
test "Native row dispatch distinguishes precommit failure from lost committed reply" {
  for reply_lost in [false, true] {
    let name = "client-row-commit-loss-" + reply_lost.to_string()
    let database = epoch_test_database(name)
    let (journal, request, _) = resume_test_approved(database)
    let claim = effect_row_test_claim(journal, request)
    let (locator, key, basis) = effect_row_test_binding(request)
    guard journal.lookup(request, true) is Ok(Retained(before)) else {
      fail("Run missing")
    }
    assert_true(
      journal.record_effect_row_dispatch(
        claim,
        locator,
        key,
        basis,
        () => true,
        () => {
          if reply_lost {
            client_test_fail_commit_reply(database, 1)
          } else {
            client_test_fail_commit(database, 1)
          }
          1001L
        },
      )
      is Err(TransactionUnknown),
    )
    if !reply_lost {
      database.rollback().unwrap()
    }
    database.close_checked().unwrap()
    let reopened = epoch_test_database(name)
    let journal = open_native_client_run_journal(reopened, 8).unwrap()
    guard journal.lookup(request, true) is Ok(Retained(restored)) else {
      fail("original Run missing")
    }
    assert_eq(
      restored.revision,
      before.revision + (if reply_lost { 1L } else { 0L }),
    )
    assert_eq(
      restored.checkpoint.unwrap().effect_ledger.length(),
      if reply_lost {
        2
      } else {
        0
      },
    )
    let next = effect_row_test_claim(
      journal,
      request,
      claimant="host-second",
      at=1100L,
    )
    let action = journal
      .record_effect_row_dispatch(next, locator, key, basis, () => true, () => {
        1101L
      })
      .unwrap()
    if reply_lost {
      assert_true(action is OriginalRowRetained(_))
    } else {
      assert_true(action is DispatchRecorded(_))
    }
    reopened.close_checked().unwrap()
  }
}

///|
test "Native ledger custody refuses missing chain duplicate entry and changed immutable basis" {
  let database = epoch_test_database("client-row-custody")
  let (journal, request, _) = resume_test_approved(database)
  let claim = effect_row_test_claim(journal, request)
  let (locator, key, basis) = effect_row_test_binding(request)
  guard journal.record_effect_row_dispatch(
      claim,
      locator,
      key,
      basis,
      () => true,
      () => 1001L,
    )
    is Ok(DispatchRecorded(_)) else {
    fail("dispatch missing")
  }
  guard journal.lookup(request, true) is Ok(Retained(record)) else {
    fail("Run missing")
  }
  let checkpoint = record.checkpoint.unwrap()
  let entries = checkpoint.effect_ledger
  for
    corrupt in [
      [entries[1]],
      [entries[0], entries[0]],
      [entries[1], entries[0]],
    ] {
    assert_true(
      read_checkpoint_record(
        checkpoint_record_body({ ..checkpoint, effect_ledger: corrupt, }).unwrap(),
        record.definition,
      )
      is Err(InvalidMaterial),
    )
  }
  let changed = @effect.prepare_effect_ledger_basis(
    @host.client_request_logical_scope(request),
    locator,
    key,
    basis.unit_definition_cid,
    basis.original_membership_cid,
    basis.intent_fingerprint_cid,
    "sha256:" + "9".repeat(64),
    basis.recovery_contract_cid,
    basis.capability,
    basis.reservation_evidence_cid,
    basis.retention_contract_cid,
  ).unwrap()
  assert_true(
    journal.record_effect_row_dispatch(
      claim,
      locator,
      key,
      changed,
      () => true,
      () => 1002L,
    )
    is Err(Checkpoint(InvalidMaterial)),
  )
  database.close_checked().unwrap()
}

///|
test "Native missing or rewritten row history is refused against independent original custody" {
  for mutation in ["erase-history", "rewrite-witness", "repeat-witness"] {
    let name = "client-row-anchor-" + mutation
    let database = epoch_test_database(name)
    let (journal, request, _) = resume_test_approved(database)
    let claim = effect_row_test_claim(journal, request)
    let (locator, key, basis) = effect_row_test_binding(request)
    guard journal.record_effect_row_dispatch(
        claim,
        locator,
        key,
        basis,
        () => true,
        () => 1001L,
      )
      is Ok(DispatchRecorded(_)) else {
      fail("original dispatch missing")
    }
    guard journal.lookup(request, true) is Ok(Retained(record)) else {
      fail("Run missing")
    }
    let scope = @host.client_request_scope_cid(request)
    if mutation == "erase-history" {
      let corrupt = {
        ..record,
        checkpoint: Some({ ..record.checkpoint.unwrap(), effect_ledger: [], }),
      }
      database
      .compare_exchange(
        "client_runs",
        scope,
        record.revision,
        run_record_body(corrupt).unwrap(),
      )
      .unwrap()
      |> ignore
    } else {
      let witness = database.read("client_effect_custody", scope).unwrap()
      database
      .compare_exchange(
        "client_effect_custody",
        scope,
        witness.revision,
        if mutation == "rewrite-witness" {
          b"not-the-original-chain"
        } else {
          witness.body
        },
      )
      .unwrap()
      |> ignore
    }
    assert_true(journal.lookup(request, true) is Err(CustodyLost))
    assert_true(
      journal.restore_effect_row_observation(request, locator, () => true)
      is Err(CustodyLost),
    )
    assert_true(
      journal.record_effect_row_dispatch(
        claim,
        locator,
        key,
        basis,
        () => true,
        () => 1002L,
      )
      is Err(CustodyLost),
    )
    let corrupt_run = database.read("client_runs", scope).unwrap()
    let corrupt_witness = database.read("client_effect_custody", scope).unwrap()
    database.close_checked().unwrap()
    let reopened = epoch_test_database(name)
    assert_true(open_native_client_run_journal(reopened, 8) is Ok(_))
    assert_true(run_journal_custody(reopened, 8) is Err(CustodyLost))
    let after_run = reopened.read("client_runs", scope).unwrap()
    let after_witness = reopened.read("client_effect_custody", scope).unwrap()
    assert_eq(after_run.body, corrupt_run.body)
    assert_eq(after_run.revision, corrupt_run.revision)
    assert_eq(after_witness.body, corrupt_witness.body)
    assert_eq(after_witness.revision, corrupt_witness.revision)
    reopened.close_checked().unwrap()
  }
}

///|
test "Native retained Checkpoint without its original custody witness is not repaired" {
  let source = epoch_test_database("client-row-witness-source")
  let (_, _, approved) = resume_test_approved(source)
  let database = epoch_test_database("client-row-witness-missing")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "checkpoint-request", "checkpoint-run",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  journal.reserve_dispatch(request, true).unwrap() |> ignore
  journal.claim_physical_start(request, true).unwrap() |> ignore
  guard journal.lookup(request, true) is Ok(Retained(before)) else {
    fail("Run missing")
  }
  // Copying an otherwise valid original record must not recreate its missing
  // physical custody. No test invokes the fresh initializer as repair.
  let copied = { ..before, checkpoint: approved.checkpoint, }
  database
  .compare_exchange(
    "client_runs",
    @host.client_request_scope_cid(request),
    before.revision,
    run_record_body(copied).unwrap(),
  )
  .unwrap()
  |> ignore
  assert_true(journal.lookup(request, true) is Err(CustodyLost))
  assert_true(run_journal_custody(database, 8) is Err(CustodyLost))
  let scope = @host.client_request_scope_cid(request)
  let before_initialization = database.read("client_runs", scope).unwrap()
  assert_true(
    journal.transaction(() => {
      initialize_native_client_run_journal_rows(database)
    })
    is Err(CustodyLost),
  )
  let after_initialization = database.read("client_runs", scope).unwrap()
  assert_eq(after_initialization.body, before_initialization.body)
  assert_eq(after_initialization.revision, before_initialization.revision)
  assert_true(
    database.read("client_effect_custody", scope) is Err(@sqlite.NotFound),
  )
  database.close_checked().unwrap()
  source.close_checked().unwrap()
}

///|
test "Native row storage capacity refusal leaves both original history and custody unchanged" {
  let database = epoch_test_database("client-row-bounded-storage")
  let (journal, request, _) = resume_test_approved(database)
  let claim = effect_row_test_claim(journal, request)
  let mut refused = false
  for row = 0; row < 128; row = row + 1 {
    let (locator, key, basis) = effect_row_test_binding(
      request,
      row="row-" + row.to_string(),
    )
    guard journal.lookup(request, true) is Ok(Retained(before)) else {
      fail("original Run missing")
    }
    let witness = database
      .read("client_effect_custody", @host.client_request_scope_cid(request))
      .unwrap()
    match
      journal.record_effect_row_dispatch(
        claim,
        locator,
        key,
        basis,
        () => true,
        () => 1001L,
      ) {
      Ok(DispatchRecorded(_)) => ()
      Err(Physical(@sqlite.BodyTooLarge))
      | Err(CapacityExceeded)
      | Err(Encoding) => {
        refused = true
        assert_true(
          journal.lookup_effect_row(request, locator, () => true) is Ok(None),
        )
        guard journal.lookup(request, true) is Ok(Retained(after)) else {
          fail("original custody lost")
        }
        assert_eq(after.revision, before.revision)
        assert_eq(
          after.checkpoint.unwrap().effect_ledger.length(),
          before.checkpoint.unwrap().effect_ledger.length(),
        )
        let restored = database
          .read(
            "client_effect_custody",
            @host.client_request_scope_cid(request),
          )
          .unwrap()
        assert_eq(restored.body, witness.body)
        assert_eq(restored.revision, witness.revision)
        break
      }
      _ =>
        fail(
          "capacity diagnostic must not authorize a dispatch or report another row's result",
        )
    }
  }
  assert_true(refused)
  database.close_checked().unwrap()
  let reopened = epoch_test_database("client-row-bounded-storage")
  assert_true(open_native_client_run_journal(reopened, 8) is Ok(_))
  reopened.close_checked().unwrap()
}
