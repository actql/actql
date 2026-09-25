///|
pub(all) enum EffectRowOutcomeIssue {
  InvalidRow
  ForeignRow
  InvalidDispatch
  ForeignResponse
  Encoding
  Outcome(PublicationContractIssue)
} derive(Debug)

///|
/// An in-process fact issued from bounded response bytes. It is not physical
/// custody: the Host must first verify the saved response and exact dispatch
/// inventory. Only this issuer can construct the opaque value.
struct EffectSavedResponseEvidence {
  dispatch_entry_cids : Array[String]
  credential_use_cid : String
  physical_sha256 : String
  byte_count : Int
  http_status_code : Int
}

///|
pub fn admit_effect_saved_response_evidence(
  dispatch_entry_cids : Array[String],
  credential_use_cid : String,
  response_bytes : Bytes,
  http_status_code : Int,
  max_response_bytes : Int,
) -> Result[EffectSavedResponseEvidence, EffectRowOutcomeIssue] {
  if dispatch_entry_cids.length() == 0 ||
    !valid_contract_cid(credential_use_cid) ||
    dispatch_entry_cids.any(entry => !valid_contract_cid(entry)) {
    return Err(InvalidDispatch)
  }
  if http_status_code < 100 ||
    http_status_code > 599 ||
    max_response_bytes < 1 ||
    response_bytes.length() > max_response_bytes {
    return Err(ForeignResponse)
  }
  let seen : Array[String] = []
  for entry in dispatch_entry_cids {
    if seen.contains(entry) {
      return Err(InvalidDispatch)
    }
    seen.push(entry)
  }
  Ok({
    dispatch_entry_cids,
    credential_use_cid,
    physical_sha256: @sha.hex(response_bytes),
    byte_count: response_bytes.length(),
    http_status_code,
  })
}

///|
/// Check a typed provider projection against one admitted Preview row. This
/// establishes neither response custody nor a terminal outcome receipt.
pub fn check_effect_preview_row_outcome(
  preview : EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  projected_row_cid : String,
  outcome_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, EffectRowOutcomeIssue] {
  guard effect_preview_row_identity(preview, member_index, row_index)
    is Some(expected) else {
    return Err(InvalidRow)
  }
  if projected_row_cid != expected {
    return Err(ForeignRow)
  }
  parse_effect_outcome_shape(outcome_wire, max_wire_bytes, max_nodes, max_depth)
  .map(_ => ())
  .map_err(issue => Outcome(issue))
}

///|
/// Seal one bounded, saved physical response and one admitted typed projection
/// to an exact Preview row and dispatch. The caller must first durably retain
/// the response under that dispatch; this issuer does not itself provide
/// physical custody or authorize a terminal Ledger transition.
pub fn issue_effect_row_outcome_receipt(
  preview : EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  dispatch_entry_cid : String,
  credential_use_cid : String,
  response_bytes : Bytes,
  http_status_code : Int,
  outcome_wire : String,
  max_response_bytes : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, EffectRowOutcomeIssue] {
  let response = match
    admit_effect_saved_response_evidence(
      [dispatch_entry_cid],
      credential_use_cid,
      response_bytes,
      http_status_code,
      max_response_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  issue_effect_row_outcome_receipt_from_response(
    preview, member_index, row_index, dispatch_entry_cid, response, outcome_wire,
    max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// Reuse one admitted digest and bounded byte count across ordered batch
/// rows. This does not replace Store custody or external re-admission.
pub fn issue_effect_row_outcome_receipt_from_response(
  preview : EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  dispatch_entry_cid : String,
  response : EffectSavedResponseEvidence,
  outcome_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, EffectRowOutcomeIssue] {
  guard effect_preview_member_identity(preview, member_index)
    is Some(member_cid) &&
    effect_preview_row_identity(preview, member_index, row_index)
    is Some(row_cid) else {
    return Err(InvalidRow)
  }
  if !response.dispatch_entry_cids.contains(dispatch_entry_cid) {
    return Err(InvalidDispatch)
  }
  let outcome = match
    parse_effect_outcome_shape(
      outcome_wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Outcome(issue))
  }
  // A typed unknown is not evidence for a terminal row transition.
  if @json.object_field(outcome, "state") is Some(@json.String("unknown")) {
    return Err(ForeignResponse)
  }
  let outcome_cid = @json.cid_value(
    outcome, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "credential_use_cid")
    @encode.string_value(writer, response.credential_use_cid)
    @encode.key(writer, "dispatch_entry_cid")
    @encode.string_value(writer, dispatch_entry_cid)
    @encode.key(writer, "effect_member_preview_cid")
    @encode.string_value(writer, member_cid)
    @encode.key(writer, "effect_preview_cid")
    @encode.string_value(writer, effect_preview_semantic_identity(preview))
    @encode.key(writer, "http_status_code")
    @encode.number_value(writer, response.http_status_code.to_double())
    @encode.key(writer, "response_byte_count")
    @encode.number_value(writer, response.byte_count.to_double())
    @encode.key(writer, "response_physical_sha256")
    @encode.string_value(writer, response.physical_sha256)
    @encode.key(writer, "row_preview_cid")
    @encode.string_value(writer, row_cid)
    @encode.key(writer, "typed_outcome")
    @json.emit_value(outcome, writer)
    @encode.key(writer, "typed_outcome_cid")
    @encode.string_value(writer, outcome_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-effect-row-outcome-receipt/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(Encoding)
  }
  let body = @encode.finish(writer) catch { _ => return Err(Encoding) }
  seal_publication_contract(
    "effect_row_outcome_receipt", body, max_wire_bytes, max_nodes, max_depth,
  ).map_err(issue => Outcome(issue))
}

///|
/// Re-admit a retained Receipt against the exact saved response and row.
/// Shape and self-CID checks alone cannot establish these cross-references.
pub fn admit_effect_row_outcome_receipt(
  preview : EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  dispatch_entry_cid : String,
  credential_use_cid : String,
  response_bytes : Bytes,
  http_status_code : Int,
  receipt_wire : String,
  max_response_bytes : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, EffectRowOutcomeIssue] {
  let response = match
    admit_effect_saved_response_evidence(
      [dispatch_entry_cid],
      credential_use_cid,
      response_bytes,
      http_status_code,
      max_response_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  admit_effect_row_outcome_receipt_from_response(
    preview, member_index, row_index, dispatch_entry_cid, response, receipt_wire,
    max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// Re-admit a retained row Receipt against a response fact already checked
/// in this invocation. External reads must construct a fresh fact from bytes.
pub fn admit_effect_row_outcome_receipt_from_response(
  preview : EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  dispatch_entry_cid : String,
  response : EffectSavedResponseEvidence,
  receipt_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, EffectRowOutcomeIssue] {
  let candidate = match
    admit_publication_contract(
      "effect_row_outcome_receipt", receipt_wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Outcome(issue))
  }
  guard @json.object_field(candidate.value, "typed_outcome")
    is Some(typed_outcome) else {
    return Err(ForeignRow)
  }
  let typed_wire = @json.stringify_value(
    typed_outcome, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  let expected = match
    issue_effect_row_outcome_receipt_from_response(
      preview, member_index, row_index, dispatch_entry_cid, response, typed_wire,
      max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if candidate.identity != expected.identity || candidate.wire != expected.wire {
    return Err(ForeignResponse)
  }
  Ok(candidate)
}

///|
/// Only a fully admitted terminal provider result can select a terminal
/// Ledger state. An unknown response has no terminal Receipt in this path.
pub fn effect_row_outcome_receipt_terminal_state(
  receipt : PublicationContract,
) -> String? {
  if receipt.name != "effect_row_outcome_receipt" {
    return None
  }
  guard @json.object_field(receipt.value, "typed_outcome") is Some(outcome) &&
    @json.object_field(outcome, "state") is Some(@json.String(state)) else {
    return None
  }
  if state == "applied" || state == "accepted" || state == "failed" {
    Some(state)
  } else {
    None
  }
}

///|
pub fn effect_row_outcome_receipt_dispatch_identity(
  receipt : PublicationContract,
) -> String? {
  if receipt.name != "effect_row_outcome_receipt" {
    return None
  }
  contract_string(receipt, "dispatch_entry_cid")
}

///|
pub fn effect_row_outcome_receipt_row_identity(
  receipt : PublicationContract,
) -> String? {
  if receipt.name != "effect_row_outcome_receipt" {
    return None
  }
  match @json.object_field(receipt.value, "row_preview_cid") {
    Some(@json.String(cid)) => Some(cid)
    _ => None
  }
}
