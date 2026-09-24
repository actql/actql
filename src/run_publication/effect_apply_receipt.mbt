///|
pub(all) enum EffectApplyReceiptBindingIssue {
  Receipt(PublicationContractIssue)
  InvalidMember
  ForeignPreview
  ForeignMember
  RowPartitionMismatch
} derive(Debug)

///|
fn effect_receipt_row_ids(
  value : @json.CanonicalValue,
  field : String,
) -> Array[String]? {
  guard @json.object_field(value, field) is Some(@json.Array(frozen)) else {
    return None
  }
  let output : Array[String] = []
  for item in @json.array_values(frozen) {
    match item {
      @json.String(cid) => output.push(cid)
      _ => return None
    }
  }
  Some(output)
}

///|
fn effect_receipt_failed_row_ids(
  value : @json.CanonicalValue,
) -> Array[String]? {
  guard @json.object_field(value, "failed") is Some(@json.Array(frozen)) else {
    return None
  }
  let output : Array[String] = []
  for item in @json.array_values(frozen) {
    match @json.object_field(item, "row_preview_cid") {
      Some(@json.String(cid)) => output.push(cid)
      _ => return None
    }
  }
  Some(output)
}

///|
/// Read one row's partition from an admitted member receipt. The caller must
/// separately establish that the corresponding Ledger head is durable and
/// that any terminal row receipt owns the saved physical response.
pub fn effect_apply_receipt_row_state(
  receipt : PublicationContract,
  row_cid : String,
) -> String? {
  if receipt.name != "effect_apply_receipt" {
    return None
  }
  for field in ["applied", "accepted", "unknown", "unattempted"] {
    match effect_receipt_row_ids(receipt.value, field) {
      Some(rows) if rows.contains(row_cid) => return Some(field)
      _ => ()
    }
  }
  match effect_receipt_failed_row_ids(receipt.value) {
    Some(rows) if rows.contains(row_cid) => Some("failed")
    _ => None
  }
}

///|
fn effect_apply_receipt_consistent(value : @json.CanonicalValue) -> Bool {
  let applied = match effect_receipt_row_ids(value, "applied") {
    Some(rows) => rows
    None => return false
  }
  let accepted = match effect_receipt_row_ids(value, "accepted") {
    Some(rows) => rows
    None => return false
  }
  let unknown = match effect_receipt_row_ids(value, "unknown") {
    Some(rows) => rows
    None => return false
  }
  let unattempted = match effect_receipt_row_ids(value, "unattempted") {
    Some(rows) => rows
    None => return false
  }
  let failed = match effect_receipt_failed_row_ids(value) {
    Some(rows) => rows
    None => return false
  }
  let seen : Array[String] = []
  for rows in [applied, accepted, unknown, failed, unattempted] {
    for row in rows {
      if seen.contains(row) {
        return false
      }
      seen.push(row)
    }
  }
  let status = match @json.object_field(value, "status") {
    Some(@json.String(text)) => text
    _ => return false
  }
  let outcome = match @json.object_field(value, "outcome") {
    Some(body) =>
      match @json.object_field(body, "state") {
        Some(@json.String(text)) => text
        _ => return false
      }
    _ => return false
  }
  let stale = @json.object_field(value, "stale_error_cid") is Some(_)
  match status {
    "stale_preview" =>
      stale &&
      applied.is_empty() &&
      accepted.is_empty() &&
      unknown.is_empty() &&
      failed.is_empty() &&
      outcome == "failed"
    "unknown_outcome" => !stale && !unknown.is_empty() && outcome == "unknown"
    "applied" =>
      !stale &&
      accepted.is_empty() &&
      unknown.is_empty() &&
      failed.is_empty() &&
      unattempted.is_empty() &&
      outcome == "applied"
    "accepted" =>
      !stale &&
      !accepted.is_empty() &&
      unknown.is_empty() &&
      failed.is_empty() &&
      unattempted.is_empty() &&
      outcome == "accepted"
    "partial_failure" =>
      !stale &&
      unknown.is_empty() &&
      (!failed.is_empty() || !unattempted.is_empty()) &&
      (!applied.is_empty() || !accepted.is_empty()) &&
      outcome == "failed"
    "failed" =>
      !stale &&
      applied.is_empty() &&
      accepted.is_empty() &&
      unknown.is_empty() &&
      (!failed.is_empty() || !unattempted.is_empty()) &&
      outcome == "failed"
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
  if contract_string(receipt, "effect_member_preview_cid") !=
    preview.member_cids.get(member_index) {
    return Err(ForeignMember)
  }
  let seen : Array[String] = []
  for field in ["applied", "accepted", "unknown", "unattempted"] {
    let rows = match effect_receipt_row_ids(receipt.value, field) {
      Some(rows) => rows
      None => return Err(RowPartitionMismatch)
    }
    for row in rows {
      if !expected_rows.contains(row) || seen.contains(row) {
        return Err(RowPartitionMismatch)
      }
      seen.push(row)
    }
  }
  let failed = match effect_receipt_failed_row_ids(receipt.value) {
    Some(rows) => rows
    None => return Err(RowPartitionMismatch)
  }
  for row in failed {
    if !expected_rows.contains(row) || seen.contains(row) {
      return Err(RowPartitionMismatch)
    }
    seen.push(row)
  }
  if seen.length() != expected_rows.length() {
    return Err(RowPartitionMismatch)
  }
  Ok(receipt)
}
