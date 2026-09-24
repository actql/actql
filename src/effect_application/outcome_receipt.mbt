///|
pub(all) enum EffectRowReceiptCommitIssue {
  ForeignClaim
  ForeignReceipt
  InvalidTransition
} derive(Debug)

///|
/// Select a terminal row transition only from the exact saved response and
/// admitted Preview row. The physical adapter must retain the response and
/// receipt first, then atomically CAS the returned Ledger entry into the
/// durable head. Exact replay returns the same already-terminal entry.
pub fn issue_effect_row_receipt_terminal_entry(
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  scope : LogicalRequestScope,
  locator : LogicalItemLocator,
  key : EffectDispatchKey,
  canonical_request_cid : String,
  current : EffectLedgerEntry,
  history : Array[EffectLedgerEntry],
  dispatch_entry_cid : String,
  credential_use_cid : String,
  response_bytes : Bytes,
  http_status_code : Int,
  receipt_wire : String,
  max_response_bytes : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[EffectLedgerEntry, EffectRowReceiptCommitIssue] {
  guard @publication.effect_preview_member_kind(preview, member_index)
    is Some(effect_kind) &&
    @publication.effect_preview_ordered_row_identity(
      preview, member_index, row_index,
    )
    is Some(row_cid) else {
    return Err(ForeignClaim)
  }
  if admit_effect_single_row(
      preview, member_index, row_index, effect_kind, scope, row_cid, locator, key,
    )
    is Err(_) ||
    current.logical_request_scope_cid != logical_request_scope_cid(scope) ||
    current.logical_item_locator_cid != locator.cid ||
    current.dispatch_key_cid != key.cid ||
    current.effect_preview_cid !=
    @publication.effect_preview_semantic_identity(preview) ||
    current.canonical_request_cid != canonical_request_cid {
    return Err(ForeignClaim)
  }
  let receipt = match
    @publication.admit_effect_row_outcome_receipt(
      preview, member_index, row_index, dispatch_entry_cid, credential_use_cid, response_bytes,
      http_status_code, receipt_wire, max_response_bytes, max_wire_bytes, max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignReceipt)
  }
  guard @publication.effect_row_outcome_receipt_terminal_state(receipt)
    is Some(state) else {
    return Err(ForeignReceipt)
  }
  let receipt_cid = @publication.publication_contract_identity(receipt)
  if history.is_empty() || history[history.length() - 1].cid != current.cid {
    return Err(ForeignClaim)
  }
  let mut previous : EffectLedgerEntry? = None
  let mut dispatch_seen = false
  for entry in history {
    if !effect_ledger_entry_follows(previous, entry) {
      return Err(ForeignClaim)
    }
    if entry.cid == dispatch_entry_cid {
      if entry.state != Dispatching || dispatch_seen {
        return Err(ForeignClaim)
      }
      dispatch_seen = true
    } else if dispatch_seen &&
      entry.state != Unknown &&
      !(entry.cid == current.cid &&
      (
        current.state == Applied ||
        current.state == Accepted ||
        current.state == Failed
      )) {
      return Err(ForeignClaim)
    }
    previous = Some(entry)
  }
  if !dispatch_seen {
    return Err(ForeignClaim)
  }
  if current.state == Applied ||
    current.state == Accepted ||
    current.state == Failed {
    if current.outcome_receipt_cid == Some(receipt_cid) &&
      ledger_state_text(current.state) == state {
      return Ok(current)
    }
    return Err(InvalidTransition)
  }
  match
    issue_next_effect_ledger_entry(
      current,
      state,
      Some(receipt_cid),
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => Ok(value)
    Err(_) => Err(InvalidTransition)
  }
}
