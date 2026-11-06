///|
fn response_test_dispatch(
  name : String,
) -> (
  @sqlite.Database,
  NativeClientRunJournal,
  @host.ClientRequestIdentity,
  @effect.LogicalItemLocator,
  NativeClientEffectDispatchClaim,
) raise {
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
    is Ok(DispatchRecorded(dispatch)) else {
    fail("original response dispatch missing")
  }
  (database, journal, request, locator, dispatch)
}

///|
fn response_test_value() -> @journal.NativeEffectSavedResponse {
  {
    credential_use_cid: "sha256:" + "7".repeat(64),
    status_code: 409,
    // Original wire bytes include non-JSON bytes, both Unicode spellings and
    // distinct CR/LF/CRLF. No response projection or configuration codec owns
    // these values. Expected bytes are authored independently of storage.
    body: b"\x00\xffe\xcc\x81\xc3\xa9\rX\nY\r\nZ",
  }
}

///|
test "Native original Effect response preserves exact bytes and original attempt across reopen" {
  let name = "client-effect-response-reopen"
  let (database, journal, request, locator, dispatch) = response_test_dispatch(
    name,
  )
  let response = response_test_value()
  guard journal.lookup(request, true) is Ok(Retained(before)) else {
    fail("Run missing")
  }
  assert_true(
    journal.effect_row_response(dispatch, () => true, 4096) is Ok(None),
  )
  journal.record_effect_row_response(dispatch, response, 4096).unwrap()
  guard journal.lookup(request, true) is Ok(Retained(saved)) else {
    fail("Run missing")
  }
  assert_eq(saved.revision, before.revision + 1L)
  assert_eq(
    saved.checkpoint.unwrap().effect_ledger.map(
      @effect.effect_ledger_entry_wire,
    ),
    before.checkpoint.unwrap().effect_ledger.map(
      @effect.effect_ledger_entry_wire,
    ),
  )
  journal.record_effect_row_response(dispatch, response, 4096).unwrap()
  guard journal.lookup(request, true) is Ok(Retained(repeated)) else {
    fail("Run missing")
  }
  assert_eq(repeated.revision, saved.revision)
  let stored = journal
    .effect_row_response(dispatch, () => true, 4096)
    .unwrap()
    .unwrap()
  assert_eq(stored.body, b"\x00\xffe\xcc\x81\xc3\xa9\rX\nY\r\nZ")
  assert_eq(stored.status_code, 409)
  database.close_checked().unwrap()
  let reopened = epoch_test_database(name)
  let journal = open_native_client_run_journal(reopened, 8).unwrap()
  assert_true(
    journal.effect_row_response(dispatch, () => true, 4096)
    is Err(Checkpoint(InvalidMaterial)),
  )
  let original = journal
    .restore_effect_row_observation(request, locator, () => true)
    .unwrap()
    .unwrap()
  let restored = journal
    .effect_row_response(original, () => true, 4096)
    .unwrap()
    .unwrap()
  assert_eq(restored.body, response.body)
  assert_eq(restored.credential_use_cid, response.credential_use_cid)
  assert_eq(original.dispatching.cid, dispatch.dispatching.cid)
  assert_eq(original.dispatching.attempt_sequence, 1L)
  assert_false(journal.claim_physical_start(request, true).unwrap())
  reopened.close_checked().unwrap()
}

///|
test "Native saved response does not settle unknown or bypass cancellation and current disclosure" {
  let (database, journal, request, locator, dispatch) = response_test_dispatch(
    "client-effect-response-unknown",
  )
  guard journal.lookup(request, true) is Ok(Retained(before)) else {
    fail("Run missing")
  }
  journal
  .transaction(() => journal.save({ ..before, cancellation_requested: true, }))
  .unwrap()
  |> ignore
  let unknown = journal.record_effect_row_unknown(dispatch).unwrap()
  journal
  .record_effect_row_response(dispatch, response_test_value(), 4096)
  .unwrap()
  guard journal.lookup_effect_row(request, locator, () => true)
    is Ok(Some(head)) else {
    fail("unknown missing")
  }
  assert_eq(head.cid, unknown.cid)
  assert_eq(@effect.effect_ledger_entry_state_code(head), 5)
  assert_true(
    journal.effect_row_response(dispatch, () => false, 4096)
    is Err(AuthorizationDenied),
  )
  let reads = Ref(0)
  assert_true(
    journal.effect_row_response(
      dispatch,
      () => {
        reads.val += 1
        reads.val < 2
      },
      4096,
    )
    is Err(AuthorizationDenied),
  )
  assert_eq(reads.val, 2)
  guard journal.lookup(request, true) is Ok(Retained(after)) else {
    fail("Run missing")
  }
  assert_true(after.cancellation_requested)
  assert_eq(after.checkpoint.unwrap().effect_ledger.length(), 3)
  assert_true(
    journal.effect_row_response(dispatch, () => true, 4096) is Ok(Some(_)),
  )
  guard journal.lookup(request, true) is Ok(Retained(after_read)) else {
    fail("Run missing")
  }
  assert_eq(after_read.revision, after.revision)
  database.close_checked().unwrap()
}

///|
test "Native response commit loss retains original dispatch and is resolved without resend" {
  for reply_lost in [false, true] {
    let name = "client-effect-response-commit-" + reply_lost.to_string()
    let (database, journal, request, locator, dispatch) = response_test_dispatch(
      name,
    )
    let response = response_test_value()
    if reply_lost {
      client_test_fail_commit_reply(database, 1)
    } else {
      client_test_fail_commit(database, 1)
    }
    assert_true(
      journal.record_effect_row_response(dispatch, response, 4096)
      is Err(TransactionUnknown),
    )
    assert_true(
      journal.effect_row_response(dispatch, () => true, 4096) is Err(Fenced),
    )
    if !reply_lost {
      database.rollback().unwrap()
    }
    database.close_checked().unwrap()
    let reopened = epoch_test_database(name)
    let journal = open_native_client_run_journal(reopened, 8).unwrap()
    let original = journal
      .restore_effect_row_observation(request, locator, () => true)
      .unwrap()
      .unwrap()
    let saved = journal.effect_row_response(original, () => true, 4096).unwrap()
    assert_eq(saved is Some(_), reply_lost)
    assert_eq(original.dispatching.cid, dispatch.dispatching.cid)
    journal.record_effect_row_response(original, response, 4096).unwrap()
    let claimant = effect_row_test_claim(
      journal,
      request,
      claimant="host-second",
      at=1100L,
    )
    let (_, key, basis) = effect_row_test_binding(request)
    assert_true(
      journal.record_effect_row_dispatch(
        claimant,
        locator,
        key,
        basis,
        () => true,
        () => 1101L,
      )
      is Ok(OriginalRowRetained(_)),
    )
    reopened.close_checked().unwrap()
  }
}

///|
test "Native response refuses changed values foreign handles and bounded storage before committing" {
  let (database, journal, request, _, dispatch) = response_test_dispatch(
    "client-effect-response-refusals",
  )
  let response = response_test_value()
  guard journal.lookup(request, true) is Ok(Retained(before)) else {
    fail("Run missing")
  }
  assert_true(
    journal.record_effect_row_response(dispatch, response, 1)
    is Err(Physical(@sqlite.BodyTooLarge)),
  )
  assert_true(
    journal.record_effect_row_response(
      dispatch,
      { ..response, status_code: 99, },
      4096,
    )
    is Err(Checkpoint(InvalidMaterial)),
  )
  assert_true(
    journal.record_effect_row_response(
      dispatch,
      { ..response, credential_use_cid: "invalid", },
      4096,
    )
    is Err(Checkpoint(InvalidMaterial)),
  )
  assert_true(
    journal.record_effect_row_response(
      dispatch,
      { ..response, body: Bytes::make(65537, 0), },
      1048576,
    )
    is Err(Physical(@sqlite.BodyTooLarge)),
  )
  assert_true(
    journal.effect_row_response(dispatch, () => true, 4096) is Ok(None),
  )
  guard journal.lookup(request, true) is Ok(Retained(after)) else {
    fail("Run missing")
  }
  assert_eq(after.revision, before.revision)
  journal.record_effect_row_response(dispatch, response, 4096).unwrap()
  for
    changed in [
      { ..response, body: b"changed", },
      { ..response, status_code: 200, },
      { ..response, credential_use_cid: "sha256:" + "8".repeat(64), },
    ] {
    assert_true(
      journal.record_effect_row_response(dispatch, changed, 4096)
      is Err(Checkpoint(InvalidMaterial)),
    )
  }
  let foreign = open_native_client_run_journal(database, 8).unwrap()
  assert_true(
    foreign.record_effect_row_response(dispatch, response, 4096)
    is Err(Checkpoint(InvalidMaterial)),
  )
  assert_true(
    journal.effect_row_response(dispatch, () => true, 1)
    is Err(Physical(@sqlite.BodyTooLarge)),
  )
  assert_eq(
    journal.effect_row_response(dispatch, () => true, 4096).unwrap().unwrap().body,
    response.body,
  )
  database.close_checked().unwrap()
}

///|
test "Native original response witness rejects missing pairs and tampered raw custody" {
  for loss in ["meta", "bytes", "both", "tamper"] {
    let name = "client-effect-response-loss-" + loss
    let (database, journal, _, _, dispatch) = response_test_dispatch(name)
    journal
    .record_effect_row_response(dispatch, response_test_value(), 4096)
    .unwrap()
    let cid = dispatch.dispatching.cid
    if loss == "tamper" {
      database
      .compare_exchange("client_effect_response_bytes", cid, 0L, b"altered")
      .unwrap()
      |> ignore
    } else {
      for
        table in ["client_effect_response_meta", "client_effect_response_bytes"] {
        if loss != "both" && table != "client_effect_response_" + loss {
          continue
        }
        let ns = @utf8.encode(table)
        let key = @utf8.encode(cid)
        assert_true(
          submitted_test_remove_record(
            database,
            ns,
            ns.length(),
            key,
            key.length(),
          ),
        )
      }
    }
    assert_true(
      journal.effect_row_response(dispatch, () => true, 4096)
      is Err(CustodyLost),
    )
    let corrupt_meta = database.read("client_effect_response_meta", cid)
    let corrupt_bytes = database.read("client_effect_response_bytes", cid)
    database.close_checked().unwrap()
    let reopened = epoch_test_database(name)
    assert_true(open_native_client_run_journal(reopened, 8) is Ok(_))
    assert_true(run_journal_custody(reopened, 8) is Err(CustodyLost))
    for
      (table, before) in [
        ("client_effect_response_meta", corrupt_meta),
        ("client_effect_response_bytes", corrupt_bytes),
      ] {
      match (before, reopened.read(table, cid)) {
        (Ok(before), Ok(after)) => {
          assert_eq(after.body, before.body)
          assert_eq(after.revision, before.revision)
        }
        (Err(@sqlite.NotFound), Err(@sqlite.NotFound)) => ()
        _ => fail("integrity inspection changed the original response custody")
      }
    }
    reopened.close_checked().unwrap()
  }
}

///|
test "Native response custody rejects unattached rows and cannot bootstrap over them" {
  let database = epoch_test_database("client-effect-response-orphan")
  initialize_native_client_run_journal(database).unwrap()
  let body = response_test_value()
  let metadata = @journal.effect_response_record_metadata(body, 4096L).unwrap()
  let cid = "sha256:" + "9".repeat(64)
  database.insert("client_effect_response_meta", cid, metadata).unwrap()
  |> ignore
  database.insert("client_effect_response_bytes", cid, body.body).unwrap()
  |> ignore
  let journal = open_native_client_run_journal(database, 8).unwrap()
  assert_true(run_journal_custody(database, 8) is Err(CustodyLost))
  let saved_meta = database.read("client_effect_response_meta", cid).unwrap()
  let saved_bytes = database.read("client_effect_response_bytes", cid).unwrap()
  assert_eq(saved_meta.body, metadata)
  assert_eq(saved_meta.revision, 0L)
  assert_eq(saved_bytes.body, body.body)
  assert_eq(saved_bytes.revision, 0L)
  assert_true(
    journal.transaction(() => {
      initialize_native_client_run_journal_rows(database)
    })
    is Err(CustodyLost),
  )
  let after_meta = database.read("client_effect_response_meta", cid).unwrap()
  let after_bytes = database.read("client_effect_response_bytes", cid).unwrap()
  assert_eq(after_meta.body, saved_meta.body)
  assert_eq(after_meta.revision, saved_meta.revision)
  assert_eq(after_bytes.body, saved_bytes.body)
  assert_eq(after_bytes.revision, saved_bytes.revision)
  database.close_checked().unwrap()
}
