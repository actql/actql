///|
pub(all) enum EffectApplyReceiptBindingIssue {
  Receipt(PublicationContractIssue)
  InvalidMember
  ForeignPreview
  ForeignRun
  ForeignMember
  RowPartitionMismatch
} derive(Debug)

///|
fn effect_receipt_rows(
  value : @json.CanonicalValue,
) -> Array[@json.CanonicalValue]? {
  match @json.object_field(value, "rows") {
    Some(@json.Array(frozen)) => Some(@json.array_values(frozen))
    _ => None
  }
}

///|
pub fn effect_apply_receipt_row_field(
  receipt : PublicationContract,
  row_cid : String,
  field : String,
) -> String? {
  if receipt.name != "effect_apply_receipt" {
    return None
  }
  guard effect_receipt_rows(receipt.value) is Some(rows) else { return None }
  for row in rows {
    if @json.object_field(row, "row_preview_cid") is Some(@json.String(cid)) &&
      cid == row_cid {
      match @json.object_field(row, field) {
        Some(@json.String(value)) => return Some(value)
        _ => return None
      }
    }
  }
  None
}

///|
pub fn effect_apply_receipt_row_state(
  receipt : PublicationContract,
  row_cid : String,
) -> String? {
  effect_apply_receipt_row_field(receipt, row_cid, "state")
}

///|
pub fn effect_apply_receipt_row_attempt_sequence(
  receipt : PublicationContract,
  row_cid : String,
) -> Int64? {
  if receipt.name != "effect_apply_receipt" {
    return None
  }
  guard effect_receipt_rows(receipt.value) is Some(rows) else { return None }
  for row in rows {
    if @json.object_field(row, "row_preview_cid") is Some(@json.String(cid)) &&
      cid == row_cid {
      match @json.object_field(row, "attempt_sequence") {
        Some(@json.Number(value)) => return Some(value.to_int64())
        _ => return None
      }
    }
  }
  None
}

///|
fn effect_apply_receipt_consistent(value : @json.CanonicalValue) -> Bool {
  guard effect_receipt_rows(value) is Some(rows) else { return false }
  let seen : Array[String] = []
  let batch_states : Map[String, String] = Map([])
  let mut success = false
  let mut accepted = false
  let mut unknown = false
  let mut failure = false
  let mut dispatched = false
  for row in rows {
    guard @json.object_field(row, "row_preview_cid") is Some(@json.String(cid)) &&
      @json.object_field(row, "state") is Some(@json.String(state)) else {
      return false
    }
    if seen.contains(cid) {
      return false
    }
    seen.push(cid)
    if @json.object_field(row, "batch_result_cid")
      is Some(@json.String(batch_cid)) {
      match batch_states.get(batch_cid) {
        Some(prior) if (
            prior == "rolled_back" &&
            (state == "applied" || state == "accepted")
          ) ||
          (
            state == "rolled_back" &&
            (prior == "applied" || prior == "accepted")
          ) => return false
        _ => ()
      }
      batch_states[batch_cid] = state
    }
    match state {
      "applied" => {
        success = true
        dispatched = true
      }
      "accepted" => {
        success = true
        accepted = true
        dispatched = true
      }
      "unknown" => {
        unknown = true
        dispatched = true
      }
      "failed" | "rolled_back" => {
        failure = true
        dispatched = true
      }
      "unattempted" => failure = true
      _ => return false
    }
  }
  let status = match @json.object_field(value, "status") {
    Some(@json.String(text)) => text
    _ => return false
  }
  let stale = @json.object_field(value, "stale_error_cid") is Some(_)
  match status {
    "stale_preview" => stale && !dispatched && !success
    "unknown_outcome" => !stale && unknown
    "applied" => !stale && !unknown && !failure && !accepted
    "accepted" => !stale && !unknown && !failure && accepted
    "partial_failure" => !stale && !unknown && failure && success
    "failed" => !stale && !unknown && failure && !success
    _ => false
  }
}

///|
/// A closed, self-addressed receipt must partition exactly the rows of one
/// admitted Preview member. Shape and identity do not establish physical
/// outcome evidence; the Host must admit each terminal row fact separately.
pub fn admit_effect_apply_receipt_for_member(
  preview : EffectPreviewIdentity,
  member_index : Int,
  receipt_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, EffectApplyReceiptBindingIssue] {
  let expected_rows = match preview.row_cids.get(member_index) {
    Some(rows) => rows
    None => return Err(InvalidMember)
  }
  let receipt = match
    admit_publication_contract(
      "effect_apply_receipt", receipt_wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Receipt(issue))
  }
  if contract_string(receipt, "effect_preview_cid") !=
    Some(preview.semantic_cid) {
    return Err(ForeignPreview)
  }
  if contract_string(receipt, "run_identity_cid") !=
    Some(preview.run_identity_cid) {
    return Err(ForeignRun)
  }
  if contract_string(receipt, "effect_member_preview_cid") !=
    preview.member_cids.get(member_index) {
    return Err(ForeignMember)
  }
  let rows = match effect_receipt_rows(receipt.value) {
    Some(rows) => rows
    None => return Err(RowPartitionMismatch)
  }
  if rows.length() != expected_rows.length() {
    return Err(RowPartitionMismatch)
  }
  for index in 0..<rows.length() {
    let row = rows[index]
    let expected_cid = effect_preview_ordered_row_identity(
      preview, member_index, index,
    )
    guard @json.object_field(row, "row_preview_cid") is Some(@json.String(cid)) &&
      Some(cid) == expected_cid &&
      @json.object_field(row, "row_index") is Some(@json.Number(position)) &&
      position == index.to_double() else {
      return Err(RowPartitionMismatch)
    }
  }
  Ok(receipt)
}
