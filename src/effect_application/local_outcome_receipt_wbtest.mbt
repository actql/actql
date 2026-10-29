///|
/// Protocol-authored Common evidence. This is not a physical SQLite commit,
/// Account/approval supplier or a replacement for the retained backend receipt.
test "local row receipt uses the original Ledger and cannot permit redispatch" {
  let c = (digit : String) => "sha256:" + digit.repeat(64)
  let scope = prepare_logical_request_scope(c("a"), "request-1", 32).unwrap()
  let (wire, key) = preview_apply_test_wire(scope, "halt")
  let preview = admit_effect_preview_apply_identity(
    wire,
    c("a"),
    "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a",
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
    c("c"),
    c("d"),
    c("e"),
    c("f"),
    c("0"),
    "unavailable",
    c("1"),
    c("2"),
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
  let operation = @publication.prepare_effect_local_operation(
    preview,
    0,
    0,
    c("1"),
    c("2"),
    c("f"),
    dispatch.cid,
    c("5"),
    c("6"),
    c("a"),
  ).unwrap()
  assert_true(
    @publication.prepare_effect_local_operation_receipt(
      operation,
      @publication.Applied(c("9")),
      "{\"state\":\"applied\",\"result\":{\"Id\":3}}",
      8192,
      256,
      12,
    )
    is Err(@publication.Outcome(@publication.InvalidWire)),
  )
  let response_result = @publication.prepare_effect_local_operation_receipt(
    operation,
    @publication.Applied(c("9")),
    "{\"result\":{\"Id\":3},\"state\":\"applied\"}",
    8192,
    256,
    12,
  )
  @debug.debug_inspect(response_result.map(_ => ()), content="Ok(())")
  let response = response_result.unwrap()
  let receipt = @publication.issue_effect_row_outcome_receipt_from_local(
    preview,
    0,
    0,
    dispatch.cid,
    response,
    8192,
    256,
    12,
  ).unwrap()
  let receipt_wire = @publication.publication_contract_json(receipt)
  let terminal = issue_effect_row_receipt_terminal_entry_from_local(
    preview,
    0,
    0,
    scope,
    locator,
    key,
    c("f"),
    dispatch,
    [prepared, dispatch],
    dispatch.cid,
    response,
    receipt_wire,
    8192,
    256,
    12,
  ).unwrap()
  assert_eq(terminal.state, Applied)
  assert_eq(
    terminal.outcome_receipt_cid,
    Some(@publication.publication_contract_identity(receipt)),
  )
  let replay = issue_effect_row_receipt_terminal_entry_from_local(
    preview,
    0,
    0,
    scope,
    locator,
    key,
    c("f"),
    terminal,
    [prepared, dispatch, terminal],
    dispatch.cid,
    response,
    receipt_wire,
    8192,
    256,
    12,
  ).unwrap()
  assert_eq(replay.cid, terminal.cid)
  // The normal final Result path consumes these existing member/set Owners;
  // a local receipt must retain the same partition and disposition checks.
  let member_receipt = issue_effect_member_receipt_from_row_partition(
    preview,
    0,
    [scope],
    [locator],
    [key],
    [basis],
    [Some(terminal)],
    [false],
    [Some(receipt)],
    1,
    8192,
    256,
    12,
  ).unwrap()
  let set = @publication.issue_effect_set_apply_receipt_from_members(
    preview,
    [member_receipt],
    [false],
    8192,
    256,
    12,
  ).unwrap()
  assert_eq(
    @publication.effect_set_receipt_run_disposition(
      preview,
      @publication.publication_contract_json(set),
      [@publication.publication_contract_json(member_receipt)],
      8192,
      256,
      12,
    ).unwrap(),
    0,
  )
  assert_true(
    issue_effect_member_receipt_from_row_partition(
      preview,
      0,
      [scope],
      [locator],
      [key],
      [basis],
      [Some(terminal)],
      [true],
      [Some(receipt)],
      1,
      8192,
      256,
      12,
    )
    is Err(ActivePhysicalOwner(0)),
  )
  assert_true(
    issue_effect_member_receipt_from_row_partition(
      preview,
      0,
      [scope],
      [locator],
      [key],
      [basis],
      [Some(terminal)],
      [false],
      [None],
      1,
      8192,
      256,
      12,
    )
    is Err(MissingTerminalReceipt(0)),
  )
  let conflict_response = @publication.prepare_effect_local_operation_receipt(
    operation,
    @publication.Conflict(Some(c("9"))),
    "{\"error\":{\"code\":\"conflict\",\"message\":\"Target changed\"},\"state\":\"failed\"}",
    8192,
    256,
    12,
  ).unwrap()
  let conflict_receipt = @publication.issue_effect_row_outcome_receipt_from_local(
    preview,
    0,
    0,
    dispatch.cid,
    conflict_response,
    8192,
    256,
    12,
  ).unwrap()
  let conflict_terminal = issue_effect_row_receipt_terminal_entry_from_local(
    preview,
    0,
    0,
    scope,
    locator,
    key,
    c("f"),
    dispatch,
    [prepared, dispatch],
    dispatch.cid,
    conflict_response,
    @publication.publication_contract_json(conflict_receipt),
    8192,
    256,
    12,
  ).unwrap()
  let conflict_member = issue_effect_member_receipt_from_row_partition(
    preview,
    0,
    [scope],
    [locator],
    [key],
    [basis],
    [Some(conflict_terminal)],
    [false],
    [Some(conflict_receipt)],
    1,
    8192,
    256,
    12,
  ).unwrap()
  let conflict_set = @publication.issue_effect_set_apply_receipt_from_members(
    preview,
    [conflict_member],
    [false],
    8192,
    256,
    12,
  ).unwrap()
  assert_eq(
    @publication.effect_set_receipt_run_disposition(
      preview,
      @publication.publication_contract_json(conflict_set),
      [@publication.publication_contract_json(conflict_member)],
      8192,
      256,
      12,
    ).unwrap(),
    2,
  )
  assert_eq(
    effect_row_recovery_action_from_entry(
      locator,
      basis.intent_fingerprint_cid,
      key,
      c("f"),
      Some(terminal),
      false,
    ),
    5, // Existing ReturnApplied action, never Unknown or dispatch permission.
  )
  assert_true(
    issue_effect_row_receipt_terminal_entry_from_local(
      preview,
      0,
      0,
      scope,
      locator,
      key,
      c("0"),
      dispatch,
      [prepared, dispatch],
      dispatch.cid,
      response,
      receipt_wire,
      8192,
      256,
      12,
    )
    is Err(ForeignReceipt),
  )
  assert_true(
    issue_effect_row_receipt_terminal_entry_from_local(
      preview,
      0,
      0,
      scope,
      locator,
      key,
      c("f"),
      dispatch,
      [dispatch],
      dispatch.cid,
      response,
      receipt_wire,
      8192,
      256,
      12,
    )
    is Err(ForeignClaim),
  )
  let http_receipt = @publication.issue_effect_row_outcome_receipt(
    preview,
    0,
    0,
    dispatch.cid,
    c("5"),
    Bytes::from_array([0x7B, 0x7D]),
    200,
    "{\"result\":{\"Id\":3},\"state\":\"applied\"}",
    1024,
    8192,
    256,
    12,
  ).unwrap()
  assert_true(
    issue_effect_row_receipt_terminal_entry_from_local(
      preview,
      0,
      0,
      scope,
      locator,
      key,
      c("f"),
      dispatch,
      [prepared, dispatch],
      dispatch.cid,
      response,
      @publication.publication_contract_json(http_receipt),
      8192,
      256,
      12,
    )
    is Err(ForeignReceipt),
  )
  assert_true(
    @publication.admit_effect_row_outcome_receipt(
      preview,
      0,
      0,
      dispatch.cid,
      c("5"),
      Bytes::from_array([0x7B, 0x7D]),
      200,
      receipt_wire,
      1024,
      8192,
      256,
      12,
    )
    is Err(_),
  )
}
