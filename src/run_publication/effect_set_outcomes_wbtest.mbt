///|
fn partition_test_member(
  preview : EffectPreviewIdentity,
  member_index : Int,
  state : String,
) -> PublicationContract {
  let cid = effect_receipt_test_cid("e")
  let row = "{\"row_index\":0,\"row_preview_cid\":\"" +
    effect_preview_ordered_row_identity(preview, member_index, 0).unwrap() +
    "\",\"state\":\"" +
    state +
    "\"" +
    (if state == "unattempted" {
      ""
    } else {
      ",\"dispatch_entry_cid\":\"" +
      cid +
      "\",\"attempt_sequence\":1," +
      (if state == "unknown" {
        "\"ledger_head_cid\":\""
      } else {
        "\"outcome_receipt_cid\":\""
      }) +
      cid +
      "\"" +
      (if state == "rolled_back" {
        ",\"batch_result_cid\":\"" + cid + "\""
      } else {
        ""
      })
    }) +
    "}"
  let status = match state {
    "applied" | "accepted" => state
    "unknown" => "unknown_outcome"
    _ => "failed"
  }
  seal_publication_contract(
    "effect_apply_receipt",
    "{\"version\":\"actql-effect-apply-receipt/0.1\",\"run_identity_cid\":\"" +
    effect_preview_run_identity(preview) +
    "\",\"effect_preview_cid\":\"" +
    effect_preview_semantic_identity(preview) +
    "\",\"effect_member_preview_cid\":\"" +
    effect_preview_member_identity(preview, member_index).unwrap() +
    "\",\"rows\":[" +
    row +
    "],\"status\":\"" +
    status +
    "\"}",
    16384,
    512,
    16,
  ).unwrap()
}

///|
test "retained admitted Effect partition uses the existing Unknown writer without raw receipt admission" {
  let preview = effect_receipt_test_preview()
  for
    (state, expected) in [
      ("unattempted", "failed"),
      ("failed", "failed"),
      ("rolled_back", "failed"),
      ("unknown", "needs_reconciliation"),
      ("applied", "succeeded"),
      ("accepted", "succeeded"),
    ] {
    let member_receipt = partition_test_member(preview, 0, state)
    let set = issue_effect_set_apply_receipt_from_members(
      preview,
      [member_receipt],
      [false],
      16384,
      512,
      16,
    ).unwrap()
    let original = admit_effect_set_apply_receipt_evidence(
      preview,
      set.wire,
      [member_receipt.wire],
      16384,
      512,
      16,
    ).unwrap()
    assert_eq(effect_set_apply_receipt_run_status(original), expected)
    let projected = issue_admitted_effect_reconciliation_run_state_wire(
      original,
      "original-run",
      "2026-09-18T00:00:00.000Z",
      ["answer"],
      16384,
      512,
      16,
    )
    if state == "unknown" {
      assert_eq(
        projected.unwrap(),
        "{\"next_action\":{\"effects\":[\"WriteOne\"],\"kind\":\"reconcile\"}," +
        "\"result_availability\":{\"answer\":{\"observed_at\":\"2026-09-18T00:00:00.000Z\"," +
        "\"reason\":\"not_published\",\"state\":\"unavailable\"}},\"result_available\":false," +
        "\"run_id\":\"original-run\",\"status\":\"needs_reconciliation\"," +
        "\"updated_at\":\"2026-09-18T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"}",
      )
    } else {
      assert_true(projected is Err(ActionStatusMismatch))
    }
  }
}

///|
test "existing raw Effect reconciliation retains complete member validation and the same writer" {
  let preview = effect_receipt_test_preview()
  let member_receipt = partition_test_member(preview, 0, "unknown")
  let set = issue_effect_set_apply_receipt_from_members(
    preview,
    [member_receipt],
    [false],
    16384,
    512,
    16,
  ).unwrap()
  let admitted = admit_effect_set_apply_receipt_evidence(
    preview,
    set.wire,
    [member_receipt.wire],
    16384,
    512,
    16,
  ).unwrap()
  let raw = issue_effect_reconciliation_run_state_wire(
    preview,
    set.wire,
    [member_receipt.wire],
    "original-run",
    "2026-09-18T00:00:00.000Z",
    ["answer"],
    16384,
    512,
    16,
  ).unwrap()
  let retained = issue_admitted_effect_reconciliation_run_state_wire(
    admitted,
    "original-run",
    "2026-09-18T00:00:00.000Z",
    ["answer"],
    16384,
    512,
    16,
  ).unwrap()
  assert_eq(raw, retained)
  assert_true(
    issue_effect_reconciliation_run_state_wire(
      preview,
      set.wire,
      [],
      "original-run",
      "2026-09-18T00:00:00.000Z",
      ["answer"],
      16384,
      512,
      16,
    )
    is Err(EffectSetMismatch),
  )
  assert_true(
    issue_effect_reconciliation_run_state_wire(
      preview,
      set.wire,
      [],
      "",
      "invalid-time",
      ["answer"],
      16384,
      512,
      16,
    )
    is Err(InvalidRunId),
  )
}

///|
test "admitted Set outcomes distinguish unattempted from every entered state" {
  let preview = effect_receipt_test_preview()
  for
    (state, disposition, unattempted) in [
      ("unattempted", 2, true),
      ("failed", 2, false),
      ("rolled_back", 2, false),
      ("unknown", 1, false),
      ("applied", 0, false),
      ("accepted", 0, false),
    ] {
    let member_receipt = partition_test_member(preview, 0, state)
    let set = issue_effect_set_apply_receipt_from_members(
      preview,
      [member_receipt],
      [false],
      16384,
      512,
      16,
    ).unwrap()
    let original = admit_effect_set_apply_receipt_evidence(
      preview,
      set.wire,
      [member_receipt.wire],
      16384,
      512,
      16,
    ).unwrap()
    assert_eq(effect_set_apply_receipt_disposition(original), disposition)
    assert_eq(effect_set_apply_receipt_all_unattempted(original), unattempted)
    // Repeated getters project the same admitted original, without wire inputs.
    assert_eq(effect_set_apply_receipt_all_unattempted(original), unattempted)
  }
}

///|
test "admitted Set outcomes inspect every member and preserve full reference checks" {
  let preview = effect_receipt_test_two_member_preview()
  let first = partition_test_member(preview, 0, "unattempted")
  let second = partition_test_member(preview, 1, "rolled_back")
  let set = issue_effect_set_apply_receipt_from_members(
    preview,
    [first, second],
    [false, false],
    16384,
    512,
    16,
  ).unwrap()
  let evidence = admit_effect_set_apply_receipt_evidence(
    preview,
    set.wire,
    [first.wire, second.wire],
    16384,
    512,
    16,
  ).unwrap()
  assert_eq(effect_set_apply_receipt_disposition(evidence), 2)
  assert_false(effect_set_apply_receipt_all_unattempted(evidence))
  assert_true(
    admit_effect_set_apply_receipt_evidence(
      preview,
      set.wire,
      [first.wire],
      16384,
      512,
      16,
    )
    is Err(MemberCountMismatch),
  )
  assert_true(
    admit_effect_set_apply_receipt_evidence(
      preview,
      set.wire,
      [second.wire, first.wire],
      16384,
      512,
      16,
    )
    is Err(MemberReceipt(_, _)),
  )
  let legacy = admit_effect_set_apply_receipt_references(
    preview,
    set.wire,
    [first.wire, second.wire],
    16384,
    512,
    16,
  ).unwrap()
  assert_eq(legacy.wire, set.wire)
}
