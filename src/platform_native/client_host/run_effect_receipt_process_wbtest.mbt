///|
/// External Native writer/readers use the original saved identity and contract
/// originals. Reader phases never prepare/compile/admit or settle another Run.
/// This is physical journal acceptance, not public CLI or Provider acceptance.
test "Native terminal receipt handoff re-admits original saved custody without execution" {
  let phase = @env.get_env_var("ACTQL_TEST_NATIVE_EFFECT_RESPONSE_PHASE")
  let reply_lost = phase == Some("write-reply-lost")
  assert_true(
    phase is None ||
    phase == Some("write") ||
    phase == Some("read") ||
    reply_lost,
  )
  let name = "client-effect-receipt-process"
  if phase != Some("read") {
    let wire = Ref("")
    let (database, journal, dispatch, preview, locator, key, basis) = receipt_test_dispatch(
      name,
      preview_wire_sink=value => wire.val = value,
    )
    let response = response_test_value()
    journal.record_effect_row_response(dispatch, response, 4096).unwrap()
    journal.record_effect_row_unknown(dispatch).unwrap() |> ignore
    let receipt = if reply_lost {
      // Derive the expected receipt from the fixture's authored raw response
      // and original dispatch before attempting the failing commit call.
      let bounds = native_client_effect_ledger_limits()
      @publication.issue_effect_row_outcome_receipt(
        preview,
        0,
        0,
        dispatch.dispatching.cid,
        response.credential_use_cid,
        response.body,
        response.status_code,
        "{\"result\":{\"id\":\"001\"},\"state\":\"applied\"}",
        4096,
        bounds.max_wire_bytes,
        bounds.max_nodes,
        bounds.max_depth,
      ).unwrap()
    } else {
      receipt_test_settle(journal, dispatch, preview, locator, key, basis).unwrap().0
    }
    guard journal.lookup(dispatch.request, true) is Ok(Retained(record)) else {
      fail("original Run missing")
    }
    let revision = if reply_lost {
      record.revision + 1L
    } else {
      record.revision
    }
    for
      (field, value) in [
        (
          "request",
          @host.client_request_identity_record_wire(dispatch.request).unwrap(),
        ),
        (
          "definition",
          @publication.publication_contract_identity(record.definition),
        ),
        ("dispatch", dispatch.dispatching.cid),
        ("preview", wire.val),
        ("authoring", preview.authoring_context_cid),
        ("program", locator.program_id),
        ("node", locator.node_id),
        ("effect", locator.effect_id),
        ("correlation", locator.item_correlation_wire),
        ("request_cid", basis.canonical_request_cid),
        ("receipt", @publication.publication_contract_identity(receipt)),
        ("revision", revision.to_string()),
      ] {
      database
      .insert("test_effect_receipt_reference", field, @utf8.encode(value))
      .unwrap()
      |> ignore
    }
    if reply_lost {
      client_test_fail_commit_reply(database, 1)
      assert_true(
        receipt_test_settle(journal, dispatch, preview, locator, key, basis)
        is Err(TransactionUnknown),
      )
      assert_true(
        database.transaction_state() is Ok(@sqlite.NoActiveSqliteTransaction),
      )
      // Leave verification to the next process. No receipt read or replay on
      // the writer's connection can resolve the lost response here.
    }
    database.close_checked().unwrap()
  }
  if phase is None || phase == Some("read") {
    let database = epoch_test_database(name)
    let saved = (field : String) => {
      @utf8.decode(
        database.read("test_effect_receipt_reference", field).unwrap().body,
      )
    }
    // Original reference and contracts only: no fixture preparation or dispatch.
    let request = @host.admit_client_request_identity_record_wire(
      saved("request"),
    ).unwrap()
    let scope = @host.client_request_logical_scope(request)
    let preview = @publication.admit_effect_preview_identity(
      saved("preview"),
      saved("definition"),
      saved("authoring"),
      8192,
      256,
      12,
    ).unwrap()
    let locator = @effect.prepare_logical_item_locator(
      scope,
      saved("program"),
      saved("node"),
      saved("effect"),
      saved("correlation"),
      64,
      128,
      16,
      4,
    ).unwrap()
    let key = @effect.prepare_effect_dispatch_key(
      scope,
      @publication.effect_preview_semantic_identity(preview),
      saved("correlation"),
      128,
      16,
      4,
    ).unwrap()
    let journal = open_native_client_run_journal(database, 8).unwrap()
    let original = journal
      .restore_effect_row_observation(request, locator, () => true)
      .unwrap()
      .unwrap()
    assert_eq(original.dispatching.cid, saved("dispatch"))
    assert_eq(original.dispatching.attempt_sequence, 1L)
    for _ in 0..<2 {
      let (receipt, head) = journal
        .effect_row_receipt(
          original,
          preview,
          0,
          0,
          locator,
          key,
          saved("request_cid"),
          () => true,
          4096,
        )
        .unwrap()
        .unwrap()
      assert_eq(
        @publication.publication_contract_identity(receipt),
        saved("receipt"),
      )
      assert_eq(@effect.effect_ledger_entry_state_code(head), 2)
      assert_eq(head.attempt_sequence, 1L)
      assert_true(
        journal.effect_row_receipt(
          original,
          preview,
          0,
          0,
          locator,
          key,
          saved("request_cid"),
          () => false,
          4096,
        )
        is Err(AuthorizationDenied),
      )
      let response = journal
        .effect_row_response(original, () => true, 4096)
        .unwrap()
        .unwrap()
      assert_eq(response.body, b"\x00\xffe\xcc\x81\xc3\xa9\rX\nY\r\nZ")
      guard journal.lookup(request, true) is Ok(Retained(record)) else {
        fail("original Run missing")
      }
      assert_eq(record.revision.to_string(), saved("revision"))
      assert_eq(
        @publication.publication_contract_identity(record.definition),
        saved("definition"),
      )
      assert_false(journal.claim_physical_start(request, true).unwrap())
    }
    database.close_checked().unwrap()
  }
}
