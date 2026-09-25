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
  SetStatusMismatch
} derive(Debug)

///|
pub(all) enum EffectSetApplyReceiptIssuanceIssue {
  InvalidInventory
  MemberReceipt(Int, EffectApplyReceiptBindingIssue)
  Receipt(PublicationContractIssue)
  References(EffectSetApplyReceiptBindingIssue)
  Encoding
} derive(Debug)

///|
fn effect_receipt_has_state(
  receipt : PublicationContract,
  state : String,
) -> Bool {
  let rows = effect_receipt_rows(receipt.value).unwrap()
  for row in rows {
    if @json.object_field(row, "state") is Some(@json.String(value)) &&
      value == state {
      return true
    }
  }
  false
}

///|
fn effect_receipt_member_state(receipt : PublicationContract) -> String {
  if effect_receipt_has_state(receipt, "unknown") {
    return "unknown"
  }
  if effect_receipt_has_state(receipt, "failed") {
    return "failed"
  }
  if effect_receipt_has_state(receipt, "unattempted") {
    if effect_receipt_has_state(receipt, "applied") ||
      effect_receipt_has_state(receipt, "accepted") {
      return "failed"
    }
    return "unattempted"
  }
  if effect_receipt_has_state(receipt, "rolled_back") {
    if effect_receipt_has_state(receipt, "applied") ||
      effect_receipt_has_state(receipt, "accepted") {
      return "failed"
    }
    return "rolled_back"
  }
  if effect_receipt_has_state(receipt, "accepted") {
    return "accepted"
  }
  "applied"
}

///|
fn effect_set_receipt_status(receipts : Array[PublicationContract]) -> String {
  let mut any_applied = false
  let mut any_accepted = false
  let mut any_unknown = false
  let mut any_failed = false
  for receipt in receipts {
    any_applied = any_applied || effect_receipt_has_state(receipt, "applied")
    any_accepted = any_accepted || effect_receipt_has_state(receipt, "accepted")
    any_unknown = any_unknown || effect_receipt_has_state(receipt, "unknown")
    any_failed = any_failed ||
      effect_receipt_has_state(receipt, "failed") ||
      effect_receipt_has_state(receipt, "unattempted") ||
      effect_receipt_has_state(receipt, "rolled_back")
  }
  if any_unknown {
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
}

///|
/// Issue the complete set Receipt from one receipt per exact Preview member.
/// Replay observations are explicit physical facts; this function does not
/// infer them from row outcomes or grant apply/publication authority.
pub fn issue_effect_set_apply_receipt_from_members(
  preview : EffectPreviewIdentity,
  member_receipts : Array[PublicationContract],
  replayed : Array[Bool],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, EffectSetApplyReceiptIssuanceIssue] {
  let count = effect_preview_member_count(preview)
  if count < 1 ||
    member_receipts.length() != count ||
    replayed.length() != count {
    return Err(InvalidInventory)
  }
  for index in 0..<count {
    match
      admit_effect_apply_receipt_for_member(
        preview,
        index,
        member_receipts[index].wire,
        max_wire_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(MemberReceipt(index, issue))
    }
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-effect-set-apply-receipt/0.1")
    @encode.key(writer, "effect_preview_cid")
    @encode.string_value(writer, effect_preview_semantic_identity(preview))
    @encode.key(writer, "apply_policy")
    @encode.string_value(writer, "attempt_all")
    @encode.key(writer, "effects")
    @encode.begin_array(writer)
    for index in 0..<count {
      @encode.begin_object(writer)
      @encode.key(writer, "effect_id")
      @encode.string_value(
        writer,
        effect_preview_member_effect_id(preview, index).unwrap(),
      )
      @encode.key(writer, "effect_member_preview_cid")
      @encode.string_value(
        writer,
        effect_preview_member_identity(preview, index).unwrap(),
      )
      @encode.key(writer, "state")
      @encode.string_value(
        writer,
        effect_receipt_member_state(member_receipts[index]),
      )
      @encode.key(writer, "replayed")
      @encode.bool_value(writer, replayed[index])
      @encode.key(writer, "member_receipt_cid")
      @encode.string_value(writer, member_receipts[index].identity)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "status")
    @encode.string_value(writer, effect_set_receipt_status(member_receipts))
    @encode.end_object(writer)
  } catch {
    _ => return Err(Encoding)
  }
  let body = @encode.finish(writer) catch { _ => return Err(Encoding) }
  let issued = match
    seal_publication_contract(
      "effect_set_apply_receipt", body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Receipt(issue))
  }
  let wires = member_receipts.map(receipt => receipt.wire)
  match
    admit_effect_set_apply_receipt_references(
      preview,
      issued.wire,
      wires,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(_) => Ok(issued)
    Err(issue) => Err(References(issue))
  }
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
  }
  let expected_status = effect_set_receipt_status(receipts)
  if contract_string(set, "status") != Some(expected_status) {
    return Err(SetStatusMismatch)
  }
  Ok(set)
}
