///|
pub(all) enum EffectSetApplyReceiptBindingIssue {
  SetReceipt(PublicationContractIssue)
  MemberReceipt(Int, EffectApplyReceiptBindingIssue)
  MemberCountMismatch
  ForeignPreview
  ForeignMember(Int)
  DuplicateMember(Int)
  ForeignEffectId(Int)
  ForeignMemberReceipt(Int)
  MemberStateMismatch(Int)
  MemberOutcomeMismatch(Int)
  SetStatusMismatch
} derive(Debug)

///|
fn effect_receipt_rows_nonempty(
  receipt : PublicationContract,
  field : String,
) -> Bool {
  match @json.object_field(receipt.value, field) {
    Some(@json.Array(rows)) => !@json.array_values(rows).is_empty()
    _ => abort("admitted Effect receipt row array required")
  }
}

///|
fn effect_receipt_member_state(receipt : PublicationContract) -> String {
  if effect_receipt_rows_nonempty(receipt, "unknown") {
    return "unknown"
  }
  if effect_receipt_rows_nonempty(receipt, "failed") {
    return "failed"
  }
  if effect_receipt_rows_nonempty(receipt, "unattempted") {
    if effect_receipt_rows_nonempty(receipt, "applied") ||
      effect_receipt_rows_nonempty(receipt, "accepted") {
      return "failed"
    }
    return "unattempted"
  }
  if effect_receipt_rows_nonempty(receipt, "accepted") {
    return "accepted"
  }
  "applied"
}

///|
/// Admit the complete set-to-member receipt reference closure. This checks
/// identities and inventories, not the Site's physical outcome evidence or
/// the Host's authorization to commit the Effect Set.
pub fn admit_effect_set_apply_receipt_references(
  preview : EffectPreviewIdentity,
  set_wire : String,
  member_receipt_wires : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, EffectSetApplyReceiptBindingIssue] {
  let count = effect_preview_member_count(preview)
  if member_receipt_wires.length() != count {
    return Err(MemberCountMismatch)
  }
  let receipts : Array[PublicationContract] = []
  let members : Map[String, Int] = Map([])
  for index in 0..<count {
    let receipt = match
      admit_effect_apply_receipt_for_member(
        preview,
        index,
        member_receipt_wires[index],
        max_wire_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(MemberReceipt(index, issue))
    }
    receipts.push(receipt)
    let member_cid = effect_preview_member_identity(preview, index).unwrap()
    members[member_cid] = index
  }
  let set = match
    admit_publication_contract(
      "effect_set_apply_receipt", set_wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(SetReceipt(issue))
  }
  if contract_string(set, "effect_preview_cid") !=
    Some(effect_preview_semantic_identity(preview)) {
    return Err(ForeignPreview)
  }
  let effects = match @json.object_field(set.value, "effects") {
    Some(@json.Array(items)) => @json.array_values(items)
    _ => return Err(MemberCountMismatch)
  }
  if effects.length() != count {
    return Err(MemberCountMismatch)
  }
  let seen : Map[String, Bool] = Map([])
  let mut any_applied = false
  let mut any_accepted = false
  let mut any_unknown = false
  let mut any_failed = false
  for position in 0..<effects.length() {
    let item = effects[position]
    let member_cid = match
      @json.object_field(item, "effect_member_preview_cid") {
      Some(@json.String(value)) => value
      _ => return Err(ForeignMember(position))
    }
    let index = match members.get(member_cid) {
      Some(value) => value
      None => return Err(ForeignMember(position))
    }
    if seen.contains(member_cid) {
      return Err(DuplicateMember(position))
    }
    seen[member_cid] = true
    let effect_id = match @json.object_field(item, "effect_id") {
      Some(@json.String(value)) => value
      _ => return Err(ForeignEffectId(position))
    }
    if Some(effect_id) != effect_preview_member_effect_id(preview, index) {
      return Err(ForeignEffectId(position))
    }
    let receipt_cid = match @json.object_field(item, "member_receipt_cid") {
      Some(@json.String(value)) => value
      _ => return Err(ForeignMemberReceipt(position))
    }
    if receipt_cid != publication_contract_identity(receipts[index]) {
      return Err(ForeignMemberReceipt(position))
    }
    let state = match @json.object_field(item, "state") {
      Some(@json.String(value)) => value
      _ => return Err(MemberStateMismatch(position))
    }
    if state != effect_receipt_member_state(receipts[index]) {
      return Err(MemberStateMismatch(position))
    }
    match @json.object_field(item, "outcome") {
      Some(outcome) => {
        let outcome_state = match @json.object_field(outcome, "state") {
          Some(@json.String(value)) => value
          _ => return Err(MemberStateMismatch(position))
        }
        if outcome_state != state {
          return Err(MemberStateMismatch(position))
        }
        let member_outcome = match
          @json.object_field(receipts[index].value, "outcome") {
          Some(value) => value
          None => return Err(MemberOutcomeMismatch(position))
        }
        let set_outcome_wire = @json.stringify_value(
          outcome, max_wire_bytes, max_nodes, max_depth,
        ) catch {
          _ => return Err(MemberOutcomeMismatch(position))
        }
        let member_outcome_wire = @json.stringify_value(
          member_outcome, max_wire_bytes, max_nodes, max_depth,
        ) catch {
          _ => return Err(MemberOutcomeMismatch(position))
        }
        if set_outcome_wire != member_outcome_wire {
          return Err(MemberOutcomeMismatch(position))
        }
      }
      None => ()
    }
    any_applied = any_applied ||
      effect_receipt_rows_nonempty(receipts[index], "applied")
    any_accepted = any_accepted ||
      effect_receipt_rows_nonempty(receipts[index], "accepted")
    any_unknown = any_unknown ||
      effect_receipt_rows_nonempty(receipts[index], "unknown")
    any_failed = any_failed ||
      effect_receipt_rows_nonempty(receipts[index], "failed") ||
      effect_receipt_rows_nonempty(receipts[index], "unattempted")
  }
  let expected_status = if any_unknown {
    "unknown_outcome"
  } else if any_failed {
    if any_applied || any_accepted {
      "partial_failure"
    } else {
      "failed"
    }
  } else if any_accepted {
    "accepted"
  } else {
    "applied"
  }
  if contract_string(set, "status") != Some(expected_status) {
    return Err(SetStatusMismatch)
  }
  Ok(set)
}
