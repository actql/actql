///|
fn member_evidence_test_receipt(
  preview : @publication.EffectPreviewIdentity,
  partition : String,
  outcome : String,
) -> @publication.PublicationContract {
  let row = @publication.effect_preview_ordered_row_identity(preview, 0, 0).unwrap()
  let applied = if partition == "applied" { "[\"" + row + "\"]" } else { "[]" }
  let unknown = if partition == "unknown" { "[\"" + row + "\"]" } else { "[]" }
  let unattempted = if partition == "unattempted" {
    "[\"" + row + "\"]"
  } else {
    "[]"
  }
  let status = if partition == "unknown" {
    "unknown_outcome"
  } else if partition == "unattempted" {
    "failed"
  } else {
    "applied"
  }
  let body = "{\"version\":\"actql-effect-apply-receipt/0.1\"," +
    "\"effect_preview_cid\":\"" +
    @publication.effect_preview_semantic_identity(preview) +
    "\",\"effect_member_preview_cid\":\"" +
    @publication.effect_preview_member_identity(preview, 0).unwrap() +
    "\",\"applied\":" +
    applied +
    ",\"accepted\":[],\"unknown\":" +
    unknown +
    ",\"failed\":[],\"unattempted\":" +
    unattempted +
    ",\"status\":\"" +
    status +
    "\",\"outcome\":" +
    outcome +
    "}"
  @publication.seal_publication_contract(
    "effect_apply_receipt", body, 8192, 256, 12,
  ).unwrap()
}

///|
test "member receipt requires the exact durable terminal row evidence" {
  let authority = ledger_test_cid("a")
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let scope = prepare_logical_request_scope(authority, "request-1", 32).unwrap()
  let (wire, key) = preview_apply_test_wire(scope, "halt")
  let preview = admit_effect_preview_apply_identity(
    wire,
    authority,
    authoring,
    scope,
    [[key]],
    8192,
    256,
    12,
  ).unwrap()
  let locator = prepare_logical_item_locator(
    scope, "program-1", "node-1", "write", "\"row-1\"", 64, 128, 8, 3,
  ).unwrap()
  let basis = prepare_effect_ledger_basis(
    scope,
    locator,
    key,
    ledger_test_cid("c"),
    ledger_test_cid("d"),
    ledger_test_cid("e"),
    ledger_test_cid("f"),
    ledger_test_cid("0"),
    "unavailable",
    ledger_test_cid("1"),
    ledger_test_cid("2"),
  ).unwrap()
  let prepared = issue_prepared_effect_ledger_entry(basis, 8192, 256, 12).unwrap()
  let dispatch = issue_next_effect_ledger_entry(
    prepared,
    "dispatching",
    None,
    8192,
    256,
    12,
  ).unwrap()
  let row_receipt = @publication.issue_effect_row_outcome_receipt(
    preview,
    0,
    0,
    dispatch.cid,
    ledger_test_cid("6"),
    Bytes::from_array([0x7B, 0x7D]),
    201,
    "{\"result\":{\"id\":\"001\"},\"state\":\"applied\"}",
    8192,
    8192,
    256,
    12,
  ).unwrap()
  let terminal = issue_next_effect_ledger_entry(
    dispatch,
    "applied",
    Some(@publication.publication_contract_identity(row_receipt)),
    8192,
    256,
    12,
  ).unwrap()
  let member_receipt = member_evidence_test_receipt(
    preview, "applied", "{\"result\":{},\"state\":\"applied\"}",
  )
  let member_wire = @publication.publication_contract_json(member_receipt)
  assert_true(
    check_effect_member_receipt_row_partition_evidence(
      preview,
      0,
      [scope],
      [locator],
      [key],
      [basis],
      [Some(terminal)],
      [false],
      [Some(row_receipt)],
      member_wire,
      1,
      8192,
      256,
      12,
    )
    is Ok(_),
  )
  assert_true(
    check_effect_member_receipt_row_partition_evidence(
      preview,
      0,
      [scope],
      [locator],
      [key],
      [basis],
      [Some(terminal)],
      [false],
      [None],
      member_wire,
      1,
      8192,
      256,
      12,
    )
    is Err(MissingTerminalReceipt(0)),
  )
  let other_row_receipt = @publication.issue_effect_row_outcome_receipt(
    preview,
    0,
    0,
    dispatch.cid,
    ledger_test_cid("6"),
    Bytes::from_array([0x7B, 0x7D]),
    201,
    "{\"result\":{\"id\":\"002\"},\"state\":\"applied\"}",
    8192,
    8192,
    256,
    12,
  ).unwrap()
  assert_true(
    check_effect_member_receipt_row_partition_evidence(
      preview,
      0,
      [scope],
      [locator],
      [key],
      [basis],
      [Some(terminal)],
      [false],
      [Some(other_row_receipt)],
      member_wire,
      1,
      8192,
      256,
      12,
    )
    is Err(ForeignTerminalReceipt(0)),
  )
  assert_true(
    check_effect_member_receipt_row_partition_evidence(
      preview,
      0,
      [scope],
      [locator],
      [key],
      [basis],
      [Some(dispatch)],
      [false],
      [Some(row_receipt)],
      member_wire,
      1,
      8192,
      256,
      12,
    )
    is Err(RowPartitionMismatch(0)),
  )
  assert_true(
    check_effect_member_receipt_row_partition_evidence(
      preview,
      0,
      [scope],
      [locator],
      [key],
      [basis],
      [Some(terminal)],
      [true],
      [Some(row_receipt)],
      member_wire,
      1,
      8192,
      256,
      12,
    )
    is Err(ActivePhysicalOwner(0)),
  )
  let foreign = { ..basis, canonical_request_cid: ledger_test_cid("9"), }
  assert_true(
    check_effect_member_receipt_row_partition_evidence(
      preview,
      0,
      [scope],
      [locator],
      [key],
      [foreign],
      [Some(terminal)],
      [false],
      [Some(row_receipt)],
      member_wire,
      1,
      8192,
      256,
      12,
    )
    is Err(ForeignLedgerHead(0)),
  )
  let unknown_outcome = "{\"command_id\":\"write-1\"," +
    "\"idempotency_key\":\"key-1\",\"reason\":\"connection_lost\"," +
    "\"reconciliation_contract\":{\"cid\":\"" +
    ledger_test_cid("0") +
    "\",\"id\":\"lookup\",\"version\":\"0.1\"},\"state\":\"unknown\"}"
  let unknown_receipt = member_evidence_test_receipt(
    preview, "unknown", unknown_outcome,
  )
  assert_true(
    check_effect_member_receipt_row_partition_evidence(
      preview,
      0,
      [scope],
      [locator],
      [key],
      [basis],
      [Some(dispatch)],
      [false],
      [None],
      @publication.publication_contract_json(unknown_receipt),
      1,
      8192,
      256,
      12,
    )
    is Ok(_),
  )
  let not_started = member_evidence_test_receipt(
    preview, "unattempted", "{\"error\":{\"code\":\"NotStarted\",\"message\":\"No send\"},\"state\":\"failed\"}",
  )
  assert_true(
    check_effect_member_receipt_row_partition_evidence(
      preview,
      0,
      [scope],
      [locator],
      [key],
      [basis],
      [None],
      [false],
      [None],
      @publication.publication_contract_json(not_started),
      1,
      8192,
      256,
      12,
    )
    is Ok(_),
  )
}
