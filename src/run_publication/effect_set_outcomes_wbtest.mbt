///|
fn partition_test_member(
  preview : EffectPreviewIdentity,
  member : Int,
  state : String,
) -> PublicationContract {
  let cid = effect_receipt_test_cid("e")
  let row = "{\"row_index\":0,\"row_preview_cid\":\"" +
    effect_preview_ordered_row_identity(preview, member, 0).unwrap() +
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
    effect_preview_member_identity(preview, member).unwrap() +
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
    let member = partition_test_member(preview, 0, state)
    let set = issue_effect_set_apply_receipt_from_members(
      preview,
      [member],
      [false],
      16384,
      512,
      16,
    ).unwrap()
    let original = admit_effect_set_apply_receipt_evidence(
      preview,
      set.wire,
      [member.wire],
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
