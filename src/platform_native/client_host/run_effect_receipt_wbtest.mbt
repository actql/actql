///|
/// Protocol-authored one-row Preview for the physical receipt transaction.
/// Derived references are signing inputs, never expected statuses/results.
fn receipt_test_preview(
  run_identity? : String,
  wire_sink? : (String) -> Unit = _ => (),
) -> (@publication.EffectPreviewIdentity, @effect.EffectDispatchKey) {
  let c = (digit : String) => "sha256:" + digit.repeat(64)
  let a = c("a")
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let change = "{\"target_row_identity\":\"row-1\",\"target_guard\":{\"state\":\"version\",\"version_cid\":\"" +
    a +
    "\"},\"intended_changes\":{\"state\":\"present\",\"value\":{}},\"before\":{\"state\":\"present\",\"value\":{}},\"after\":{\"state\":\"present\",\"value\":{}},\"row_preview_cid\":\"" +
    c("3") +
    "\",\"row_idempotency_key\":\"" +
    c("4") +
    "\"}"
  let preview_member = "{\"effect_id\":\"WriteOne\",\"effect_kind\":\"update\",\"target\":\"Object\",\"mapping\":\"mapping:fixture\",\"resolved_mapping_contract_cid\":\"" +
    a +
    "\",\"effect_identity_cid\":\"" +
    a +
    "\",\"preview_strength\":\"full_diff\",\"source_binding_cid\":\"" +
    a +
    "\",\"capability_evidence_cid\":\"" +
    a +
    "\",\"authority_scope_cid\":\"" +
    a +
    "\",\"write_footprint\":{\"kind\":\"exact_targets\",\"resource_identity_scheme_cid\":\"" +
    a +
    "\",\"provider_namespace\":\"provider\",\"provider_boundary_cid\":\"" +
    a +
    "\",\"resource_kind\":\"Object\",\"provider_object_identity_cids\":[\"" +
    c("1") +
    "\"]},\"count\":1,\"max_items\":1,\"required_permissions\":[\"write\"],\"approval\":\"none\",\"on_item_failure\":\"halt\",\"changes\":[" +
    change +
    "],\"row_order\":[\"" +
    c("3") +
    "\"],\"effect_member_preview_cid\":\"" +
    a +
    "\",\"executed\":false}"
  let raw = "{\"version\":\"actql-effect-preview/0.1\",\"sensitivity\":\"private\",\"retention_class\":\"authority-evidence\",\"encryption_required\":true,\"program_semantics_cid\":\"" +
    a +
    "\",\"program_definition_cid\":\"" +
    a +
    "\",\"invocation_cid\":\"" +
    a +
    "\",\"run_identity_cid\":\"" +
    a +
    "\",\"compiled_plan_cid\":\"" +
    a +
    "\",\"check_environment_cid\":\"" +
    a +
    "\",\"authoring_context\":{\"version\":\"actql-authoring-context/0.1\",\"program_definition_cid\":\"" +
    a +
    "\",\"annotations\":[],\"authoring_context_cid\":\"" +
    authoring +
    "\"},\"barrier_provenance_cids\":[],\"model_derived\":false,\"model_task_contract_cids\":[],\"model_invocation_evidence_cids\":[],\"model_response_artifact_cids\":[],\"effects\":[" +
    preview_member +
    "],\"executed\":false,\"effect_preview_cid\":\"" +
    a +
    "\"}"
  let source = @source.parse_json_bytes_preserving(@utf8.encode(raw), {
    max_input_bytes: 8192,
    max_nodes: 256,
    max_depth: 12,
  }).unwrap()
  let canonical = @canonical.from_source(source, 256, 12, 8192, data_keys=true) catch {
    _ => abort("Preview fixture")
  }
  let wire = @canonical.stringify_value(canonical, 8192, 256, 12) catch {
    _ => abort("Preview fixture")
  }
  let row = @publication.derive_effect_preview_row_identities(
      wire, 8192, 256, 12,
    ).unwrap()[0][0]
  let with_row = wire.replace_all(old=c("3"), new=row)
  let (_, members) = @publication.derive_effect_preview_identities(
    with_row, 8192, 256, 12,
  ).unwrap()
  let with_member = with_row.replace_all(
    old="\"effect_member_preview_cid\":\"" + a + "\"",
    new="\"effect_member_preview_cid\":\"" + members[0] + "\"",
  )
  let (cid, _) = @publication.derive_effect_preview_identities(
    with_member, 8192, 256, 12,
  ).unwrap()
  let (request, _, _, definition) = journal_test_run(
    "checkpoint-request", "checkpoint-run",
  )
  let key = @effect.prepare_effect_dispatch_key(
    @host.client_request_logical_scope(request),
    cid,
    "\"row-1\"",
    128,
    16,
    4,
  ).unwrap()
  let final_wire = with_member
    .replace_all(
      old="\"effect_preview_cid\":\"" + a + "\"",
      new="\"effect_preview_cid\":\"" + cid + "\"",
    )
    .replace_all(old=c("4"), new=key.cid)
  let original_run = run_identity.unwrap_or(
    @publication.publication_contract_identity(definition),
  )
  let final_wire = final_wire.replace_all(
    old="\"run_identity_cid\":\"" + a + "\"",
    new="\"run_identity_cid\":\"" + original_run + "\"",
  )
  wire_sink(final_wire)
  let preview = @effect.admit_effect_preview_apply_identity(
    final_wire,
    original_run,
    authoring,
    @host.client_request_logical_scope(request),
    [[key]],
    8192,
    256,
    12,
  ).unwrap()
  (preview, key)
}

///|
fn receipt_test_checkpoint(
  definition : @publication.PublicationContract,
) -> @checkpoint.SealedCheckpoint {
  let original = checkpoint_test_artifact(definition)
  let (preview, _) = receipt_test_preview()
  @checkpoint.seal_checkpoint(
    {
      ..original.checkpoint,
      required_artifact_cid: @publication.effect_preview_semantic_identity(
        preview,
      ),
    },
    native_checkpoint_limits(),
  ).unwrap()
}

///|
test "export original Native receipt Checkpoint signing references" {
  let (_, _, _, definition) = journal_test_run(
    "checkpoint-request", "checkpoint-run",
  )
  println("ACTQL_CLIENT_CHECKPOINT " + receipt_test_checkpoint(definition).wire)
}

///|
fn receipt_test_dispatch(
  name : String,
  preview_wire_sink? : (String) -> Unit = _ => (),
) -> (
  @sqlite.Database,
  NativeClientRunJournal,
  NativeClientEffectDispatchClaim,
  @publication.EffectPreviewIdentity,
  @effect.LogicalItemLocator,
  @effect.EffectDispatchKey,
  @effect.EffectLedgerBasis,
) raise {
  let database = epoch_test_database(name)
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "checkpoint-request", "checkpoint-run",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  journal.reserve_dispatch(request, true).unwrap() |> ignore
  assert_true(journal.claim_physical_start(request, true).unwrap())
  let artifact = receipt_test_checkpoint(definition)
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
  guard journal.lookup(request, true) is Ok(Retained(before)) else {
    fail("original Run missing")
  }
  journal
  .wait_checkpoint(
    request,
    compiled,
    persisted,
    before.revision,
    resume_test_binding(),
    [],
    "2026-10-10T00:00:30.000Z",
    () => true,
  )
  .unwrap()
  |> ignore
  checkpoint_test_resolve(journal, request, "RECEIPT_APPROVE", () => true, () => {
    "2026-10-10T00:02:00.000Z"
  }).unwrap()
  |> ignore
  guard resume_test_claim(
      journal,
      request,
      "host-first",
      1000L,
      100L,
      resume_test_binding(),
      () => true,
      resolution_mode="RECEIPT_APPROVE",
    )
    is Ok(Claimed(claim)) else {
    fail("receipt resume claim missing")
  }
  let (preview, key) = receipt_test_preview(wire_sink=preview_wire_sink)
  let (locator, _, _) = effect_row_test_binding(
    request,
    preview=@publication.effect_preview_semantic_identity(preview),
  )
  let basis = @effect.prepare_effect_ledger_basis(
    @host.client_request_logical_scope(request),
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
  (database, journal, dispatch, preview, locator, key, basis)
}

///|
fn receipt_test_settle(
  journal : NativeClientRunJournal,
  dispatch : NativeClientEffectDispatchClaim,
  preview : @publication.EffectPreviewIdentity,
  locator : @effect.LogicalItemLocator,
  key : @effect.EffectDispatchKey,
  basis : @effect.EffectLedgerBasis,
  current? : () -> Bool = () => true,
  outcome? : String = "{\"result\":{\"id\":\"001\"},\"state\":\"applied\"}",
) -> Result[
  (@publication.PublicationContract, @effect.EffectLedgerEntry),
  NativeClientRunJournalIssue,
] {
  let result = journal.record_effect_row_receipt(
    dispatch,
    preview,
    0,
    0,
    locator,
    key,
    basis.canonical_request_cid,
    outcome,
    current,
    4096,
  )
  match result {
    Err(CustodyLost) =>
      println("Native receipt boundary: original custody refused")
    Err(Checkpoint(InvalidMaterial)) =>
      println("Native receipt boundary: common material refused")
    Err(Physical(@sqlite.BodyTooLarge)) =>
      println("Native receipt boundary: bounded storage refused")
    Err(Physical(@sqlite.Collision)) =>
      println("Native receipt boundary: physical revision collision")
    Err(TransactionUnknown) =>
      println("Native receipt boundary: commit result unknown")
    Err(AuthorizationDenied) =>
      println("Native receipt boundary: current evidence authority denied")
    Err(_) => println("Native receipt boundary: original operation refused")
    Ok(_) => ()
  }
  result
}

///|
test "Native original receipt persists common terminal and exact replay across reopen" {
  let name = "client-row-receipt-reopen"
  let (database, journal, dispatch, preview, locator, key, basis) = receipt_test_dispatch(
    name,
  )
  journal
  .record_effect_row_response(
    dispatch,
    { ..response_test_value(), status_code: 201, },
    4096,
  )
  .unwrap()
  journal.record_effect_row_unknown(dispatch).unwrap() |> ignore
  guard journal.lookup(dispatch.request, true) is Ok(Retained(before)) else {
    fail("Run missing")
  }
  let (receipt, terminal) = receipt_test_settle(
    journal, dispatch, preview, locator, key, basis,
  ).unwrap()
  assert_eq(@effect.effect_ledger_entry_state_code(terminal), 2)
  assert_eq(terminal.attempt_sequence, 1L)
  assert_eq(
    terminal.outcome_receipt_cid,
    Some(@publication.publication_contract_identity(receipt)),
  )
  guard journal.lookup(dispatch.request, true) is Ok(Retained(after)) else {
    fail("Run missing")
  }
  assert_eq(after.revision, before.revision + 1L)
  assert_eq(after.checkpoint.unwrap().effect_ledger.length(), 4)
  assert_eq(after.checkpoint.unwrap().state, before.checkpoint.unwrap().state)
  let repeated = receipt_test_settle(
    journal, dispatch, preview, locator, key, basis,
  ).unwrap()
  assert_eq(repeated.1.cid, terminal.cid)
  let read = journal
    .effect_row_receipt(
      dispatch,
      preview,
      0,
      0,
      locator,
      key,
      basis.canonical_request_cid,
      () => true,
      4096,
    )
    .unwrap()
    .unwrap()
  assert_eq(read.1.cid, terminal.cid)
  assert_true(
    journal.effect_row_receipt(
      dispatch,
      preview,
      0,
      0,
      locator,
      key,
      basis.canonical_request_cid,
      () => false,
      4096,
    )
    is Err(AuthorizationDenied),
  )
  database.close_checked().unwrap()
  let database = epoch_test_database(name)
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let original = journal
    .restore_effect_row_observation(dispatch.request, locator, () => true)
    .unwrap()
    .unwrap()
  let restored = receipt_test_settle(
    journal, original, preview, locator, key, basis,
  ).unwrap()
  assert_eq(restored.1.cid, terminal.cid)
  assert_eq(
    @publication.publication_contract_json(restored.0),
    @publication.publication_contract_json(receipt),
  )
  guard journal.lookup(dispatch.request, true) is Ok(Retained(observed)) else {
    fail("Run missing")
  }
  assert_eq(observed.revision, after.revision)
  assert_false(journal.claim_physical_start(dispatch.request, true).unwrap())
  database.close_checked().unwrap()
}

///|
test "Native original receipt refuses missing response unknown projection and changed binding" {
  let (database, journal, dispatch, preview, locator, key, basis) = receipt_test_dispatch(
    "client-row-receipt-refuse",
  )
  assert_true(
    receipt_test_settle(journal, dispatch, preview, locator, key, basis)
    is Err(Checkpoint(NeedsOriginalContinuation)),
  )
  journal
  .record_effect_row_response(dispatch, response_test_value(), 4096)
  .unwrap()
  assert_true(
    receipt_test_settle(journal, dispatch, preview, locator, key, basis, current=() => {
      false
    })
    is Err(AuthorizationDenied),
  )
  let checks = Ref(0)
  assert_true(
    receipt_test_settle(journal, dispatch, preview, locator, key, basis, current=() => {
      checks.val += 1
      checks.val < 2
    })
    is Err(AuthorizationDenied),
  )
  assert_eq(checks.val, 2)
  assert_true(
    receipt_test_settle(
      journal,
      dispatch,
      preview,
      locator,
      key,
      basis,
      outcome="{\"command_id\":\"original-write\",\"idempotency_key\":\"row-1\",\"reason\":\"response_lost\",\"reconciliation_contract\":{\"cid\":\"sha256:" +
        "a".repeat(64) +
        "\",\"id\":\"manual\",\"version\":\"0.1\"},\"state\":\"unknown\"}",
    )
    is Err(Checkpoint(InvalidMaterial)),
  )
  let (_, foreign_key, _) = effect_row_test_binding(
    dispatch.request,
    row="row-other",
    preview=@publication.effect_preview_semantic_identity(preview),
  )
  assert_true(
    receipt_test_settle(journal, dispatch, preview, locator, foreign_key, basis)
    is Err(Checkpoint(InvalidMaterial)),
  )
  assert_eq(
    journal
    .lookup_effect_row(dispatch.request, locator, () => true)
    .unwrap()
    .unwrap().cid,
    dispatch.dispatching.cid,
  )
  assert_true(
    database.scan_after("client_effect_row_receipt", "")
    is Err(@sqlite.NotFound),
  )
  database.close_checked().unwrap()
}

///|
test "Native original terminal refuses lost or tampered receipt custody without repair" {
  for loss in [true, false] {
    let name = "client-row-receipt-custody-" + loss.to_string()
    let (database, journal, dispatch, preview, locator, key, basis) = receipt_test_dispatch(
      name,
    )
    journal
    .record_effect_row_response(dispatch, response_test_value(), 4096)
    .unwrap()
    let (receipt, _) = receipt_test_settle(
      journal, dispatch, preview, locator, key, basis,
    ).unwrap()
    let cid = @publication.publication_contract_identity(receipt)
    let orphan = epoch_test_database(name + "-orphan")
    initialize_native_client_run_journal(orphan).unwrap()
    orphan
    .insert(
      "client_effect_row_receipt",
      cid,
      @utf8.encode(@publication.publication_contract_json(receipt)),
    )
    .unwrap()
    |> ignore
    let orphan_journal = open_native_client_run_journal(orphan, 8).unwrap()
    assert_true(run_journal_custody(orphan, 8) is Err(CustodyLost))
    let saved_orphan = orphan.read("client_effect_row_receipt", cid).unwrap()
    assert_eq(
      saved_orphan.body,
      @utf8.encode(@publication.publication_contract_json(receipt)),
    )
    assert_eq(saved_orphan.revision, 0L)
    assert_true(
      orphan_journal.transaction(() => {
        initialize_native_client_run_journal_rows(orphan)
      })
      is Err(CustodyLost),
    )
    let after_orphan = orphan.read("client_effect_row_receipt", cid).unwrap()
    assert_eq(after_orphan.body, saved_orphan.body)
    assert_eq(after_orphan.revision, saved_orphan.revision)
    orphan.close_checked().unwrap()
    if loss {
      let ns = @utf8.encode("client_effect_row_receipt")
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
    } else {
      database
      .compare_exchange("client_effect_row_receipt", cid, 0L, b"{}")
      .unwrap()
      |> ignore
    }
    assert_true(
      receipt_test_settle(journal, dispatch, preview, locator, key, basis)
      is Err(CustodyLost),
    )
    let corrupt_receipt = database.read("client_effect_row_receipt", cid)
    database.close_checked().unwrap()
    let reopened = epoch_test_database(name)
    assert_true(open_native_client_run_journal(reopened, 8) is Ok(_))
    assert_true(run_journal_custody(reopened, 8) is Err(CustodyLost))
    match (corrupt_receipt, reopened.read("client_effect_row_receipt", cid)) {
      (Ok(before), Ok(after)) => {
        assert_eq(after.body, before.body)
        assert_eq(after.revision, before.revision)
      }
      (Err(@sqlite.NotFound), Err(@sqlite.NotFound)) => ()
      _ => fail("integrity inspection changed the original receipt custody")
    }
    reopened.close_checked().unwrap()
  }
}

///|
test "Native original terminal and receipt commit together after lost reply" {
  for reply_lost in [false, true] {
    let name = "client-row-receipt-commit-" + reply_lost.to_string()
    let (database, journal, dispatch, preview, locator, key, basis) = receipt_test_dispatch(
      name,
    )
    journal
    .record_effect_row_response(dispatch, response_test_value(), 4096)
    .unwrap()
    if reply_lost {
      client_test_fail_commit_reply(database, 1)
    } else {
      client_test_fail_commit(database, 1)
    }
    assert_true(
      receipt_test_settle(journal, dispatch, preview, locator, key, basis)
      is Err(TransactionUnknown),
    )
    if !reply_lost {
      database.rollback().unwrap()
    }
    database.close_checked().unwrap()
    let reopened = epoch_test_database(name)
    let journal = open_native_client_run_journal(reopened, 8).unwrap()
    let head = journal
      .lookup_effect_row(dispatch.request, locator, () => true)
      .unwrap()
      .unwrap()
    assert_eq(
      @effect.effect_ledger_entry_state_code(head),
      if reply_lost {
        2
      } else {
        1
      },
    )
    let original = journal
      .restore_effect_row_observation(dispatch.request, locator, () => true)
      .unwrap()
      .unwrap()
    let (_, terminal) = receipt_test_settle(
      journal, original, preview, locator, key, basis,
    ).unwrap()
    assert_eq(terminal.attempt_sequence, 1L)
    assert_false(journal.claim_physical_start(dispatch.request, true).unwrap())
    reopened.close_checked().unwrap()
  }
}

///|
test "Native original receipt refuses another Run with the same semantic Preview and dispatch key" {
  let (database, journal, dispatch, preview, locator, key, basis) = receipt_test_dispatch(
    "client-row-receipt-foreign-run",
  )
  journal
  .record_effect_row_response(dispatch, response_test_value(), 4096)
  .unwrap()
  let (foreign, foreign_key) = receipt_test_preview(
    run_identity="sha256:" + "9".repeat(64),
  )
  assert_eq(
    @publication.effect_preview_semantic_identity(foreign),
    @publication.effect_preview_semantic_identity(preview),
  )
  assert_eq(foreign_key.cid, key.cid)
  assert_true(
    @publication.effect_preview_run_identity(foreign) !=
    @publication.effect_preview_run_identity(preview),
  )
  assert_true(
    receipt_test_settle(journal, dispatch, foreign, locator, foreign_key, basis)
    is Err(Checkpoint(InvalidMaterial)),
  )
  assert_eq(
    journal
    .lookup_effect_row(dispatch.request, locator, () => true)
    .unwrap()
    .unwrap().cid,
    dispatch.dispatching.cid,
  )
  assert_true(
    database.scan_after("client_effect_row_receipt", "")
    is Err(@sqlite.NotFound),
  )
  database.close_checked().unwrap()
}

///|
test "Native original receipt lookup refuses foreign Run even before terminal evidence exists" {
  let (database, journal, dispatch, preview, locator, key, basis) = receipt_test_dispatch(
    "client-row-receipt-foreign-lookup",
  )
  let (foreign, foreign_key) = receipt_test_preview(
    run_identity="sha256:" + "9".repeat(64),
  )
  assert_eq(
    @publication.effect_preview_semantic_identity(foreign),
    @publication.effect_preview_semantic_identity(preview),
  )
  assert_eq(foreign_key.cid, key.cid)
  assert_true(
    journal.effect_row_receipt(
      dispatch,
      foreign,
      0,
      0,
      locator,
      foreign_key,
      basis.canonical_request_cid,
      () => true,
      4096,
    )
    is Err(Checkpoint(InvalidMaterial)),
  )
  assert_true(
    journal.effect_row_receipt(
      dispatch,
      preview,
      0,
      0,
      locator,
      key,
      basis.canonical_request_cid,
      () => true,
      4096,
    )
    is Ok(None),
  )
  database.close_checked().unwrap()
}
