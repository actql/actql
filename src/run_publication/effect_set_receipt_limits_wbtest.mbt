///|
fn receipt_limits_original(
  state : String,
) -> (EffectSetApplyReceiptEvidence, PublicationContract, PublicationContract) {
  let preview = effect_receipt_test_preview()
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
  (original, set, member)
}

///|
test "Set closure tighter limits include the original member beyond the Set envelope" {
  let (original, set, member) = receipt_limits_original("applied")
  let bytes = @utf8.encode(member.wire).length()
  // Independent closed shape: root + seven fields + row object + six fields.
  assert_eq(original.member_wire_usage, Some((bytes, 15, 3)))
  assert_true(bytes > @utf8.encode(set.wire).length())
  assert_eq(
    effect_set_apply_receipt_check_limits(original, bytes, 15, 3),
    Ok(()),
  )
  // Both limits admit the Set envelope; only its larger member must refuse.
  assert_eq(publication_contract_check_limits(set, bytes - 1, 15, 3), Ok(()))
  assert_eq(
    effect_set_apply_receipt_check_limits(original, bytes - 1, 15, 3),
    Err(Encoding),
  )
  assert_eq(publication_contract_check_limits(set, bytes, 14, 3), Ok(()))
  assert_eq(
    effect_set_apply_receipt_check_limits(original, bytes, 14, 3),
    Err(Encoding),
  )
  assert_eq(
    effect_set_apply_receipt_check_limits(original, bytes, 15, 2),
    Err(Encoding),
  )
}

///|
test "Set closure usage includes every original member without retaining their trees" {
  let preview = effect_receipt_test_two_member_preview()
  let first = partition_test_member(preview, 0, "applied")
  let second = partition_test_member(preview, 1, "rolled_back")
  let set = issue_effect_set_apply_receipt_from_members(
    preview,
    [first, second],
    [false, false],
    16384,
    512,
    16,
  ).unwrap()
  let original = admit_effect_set_apply_receipt_evidence(
    preview,
    set.wire,
    [first.wire, second.wire],
    16384,
    512,
    16,
  ).unwrap()
  let bytes = Int::max(
    @utf8.encode(first.wire).length(),
    @utf8.encode(second.wire).length(),
  )
  // The second row adds the independently required rollback receipt field.
  assert_eq(original.member_wire_usage, Some((bytes, 16, 3)))
  assert_eq(
    effect_set_apply_receipt_check_limits(original, 16384, 512, 16),
    Ok(()),
  )
  assert_eq(effect_set_apply_receipt_disposition(original), 2)
}

///|
test "Set closure limits refuse absent usage and preserve Unknown disposition" {
  let (original, _, _) = receipt_limits_original("unknown")
  assert_eq(effect_set_apply_receipt_disposition(original), 1)
  assert_eq(
    effect_set_apply_receipt_check_limits(original, 16384, 512, 16),
    Ok(()),
  )
  assert_eq(effect_set_apply_receipt_disposition(original), 1)
  let unmeasured = { ..original, member_wire_usage: None, }
  assert_eq(
    effect_set_apply_receipt_check_limits(unmeasured, 16384, 512, 16),
    Err(Encoding),
  )
  assert_eq(
    effect_set_apply_receipt_check_limits(original, 0, 512, 16),
    Err(InvalidLimits),
  )
}
