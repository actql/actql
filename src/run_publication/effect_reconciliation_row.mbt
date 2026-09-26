///|
pub(all) enum EffectRowReconciliationIssue {
  Receipt(PublicationContractIssue)
  ForeignSet
  ForeignMember
  ForeignRow
  NotUnknown
  ForeignDispatch
  ForeignOutcome
  Encoding
} derive(Debug)

///|
/// Admit one reconciliation observation for an unresolved row of the original
/// member receipt. Physical evidence custody and append-only CAS remain Host
/// obligations; this never authorizes another provider request.
pub fn admit_effect_reconciliation_receipt_for_row(
  preview : EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  set_receipt : PublicationContract,
  member_receipt : PublicationContract,
  terminal_row_receipt : PublicationContract?,
  receipt_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, EffectRowReconciliationIssue] {
  guard effect_preview_member_identity(preview, member_index)
    is Some(member_cid) &&
    effect_preview_ordered_row_identity(preview, member_index, row_index)
    is Some(row_cid) else {
    return Err(ForeignRow)
  }
  let receipt = match
    admit_publication_contract(
      "effect_reconciliation_receipt", receipt_wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Receipt(issue))
  }
  if set_receipt.name != "effect_set_apply_receipt" ||
    contract_string(set_receipt, "effect_preview_cid") !=
    Some(preview.semantic_cid) ||
    contract_string(receipt, "effect_set_receipt_cid") !=
    Some(set_receipt.identity) {
    return Err(ForeignSet)
  }
  guard @json.object_field(set_receipt.value, "effects")
    is Some(@json.Array(effects)) else {
    return Err(ForeignSet)
  }
  let mut referenced = false
  for effect in @json.array_values(effects) {
    if @json.object_field(effect, "effect_member_preview_cid")
      is Some(@json.String(cid)) &&
      cid == member_cid &&
      @json.object_field(effect, "member_receipt_cid")
      is Some(@json.String(receipt_cid)) &&
      receipt_cid == member_receipt.identity {
      referenced = true
    }
  }
  if !referenced {
    return Err(ForeignSet)
  }
  if member_receipt.name != "effect_apply_receipt" ||
    contract_string(member_receipt, "effect_preview_cid") !=
    Some(preview.semantic_cid) ||
    contract_string(member_receipt, "effect_member_preview_cid") !=
    Some(member_cid) ||
    contract_string(receipt, "effect_id") !=
    effect_preview_member_effect_id(preview, member_index) ||
    contract_string(receipt, "effect_member_preview_cid") != Some(member_cid) ||
    contract_string(receipt, "prior_receipt_cid") !=
    Some(member_receipt.identity) {
    return Err(ForeignMember)
  }
  if contract_string(receipt, "run_identity_cid") !=
    Some(preview.run_identity_cid) ||
    contract_string(receipt, "effect_preview_cid") != Some(preview.semantic_cid) ||
    contract_string(receipt, "row_preview_cid") != Some(row_cid) {
    return Err(ForeignRow)
  }
  if effect_apply_receipt_row_state(member_receipt, row_cid) != Some("unknown") {
    return Err(NotUnknown)
  }
  guard @json.object_field(receipt.value, "dispatch_attempt_sequence")
    is Some(@json.Number(dispatch_attempt)) else {
    return Err(ForeignDispatch)
  }
  if contract_string(receipt, "dispatch_entry_cid") !=
    effect_apply_receipt_row_field(
      member_receipt, row_cid, "dispatch_entry_cid",
    ) ||
    contract_string(receipt, "prior_ledger_head_cid") !=
    effect_apply_receipt_row_field(member_receipt, row_cid, "ledger_head_cid") ||
    Some(dispatch_attempt.to_int64()) !=
    effect_apply_receipt_row_attempt_sequence(member_receipt, row_cid) {
    return Err(ForeignDispatch)
  }
  let terminal = @json.object_field(receipt.value, "terminal")
    is Some(@json.Bool(true))
  match (terminal, terminal_row_receipt) {
    (false, None) => ()
    (true, Some(row_receipt)) => {
      if row_receipt.name != "effect_row_outcome_receipt" ||
        contract_string(receipt, "outcome_receipt_cid") !=
        Some(row_receipt.identity) ||
        effect_row_outcome_receipt_row_identity(row_receipt) != Some(row_cid) ||
        effect_row_outcome_receipt_dispatch_identity(row_receipt) !=
        contract_string(receipt, "dispatch_entry_cid") {
        return Err(ForeignOutcome)
      }
      guard @json.object_field(receipt.value, "outcome") is Some(outcome) &&
        @json.object_field(row_receipt.value, "typed_outcome") is Some(typed) else {
        return Err(ForeignOutcome)
      }
      let outcome_wire = @json.stringify_value(
        outcome, max_wire_bytes, max_nodes, max_depth,
      ) catch {
        _ => return Err(Encoding)
      }
      let typed_wire = @json.stringify_value(
        typed, max_wire_bytes, max_nodes, max_depth,
      ) catch {
        _ => return Err(Encoding)
      }
      if outcome_wire != typed_wire {
        return Err(ForeignOutcome)
      }
    }
    _ => return Err(ForeignOutcome)
  }
  Ok(receipt)
}
