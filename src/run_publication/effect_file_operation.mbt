///|
/// Original file-operation binding DATA. Context and Resolution are bindings,
/// not grants, write-use proofs or permission to replace a target.
pub struct EffectFileOperation {
  effect_preview_cid : String
  member_preview_cid : String
  row_preview_cid : String
  installation_cid : String
  target_cid : String
  canonical_request_cid : String
  dispatch_entry_cid : String
  authorization_context_cid : String
  resolution_cid : String
  target_version_cid : String
}

///|
/// A bounded byte/generation observation. Only the Native physical owner can
/// establish a replacement ACK; this pure constructor cannot do so.
struct EffectFileReplacementEvidence {
  physical_sha256 : String
  byte_count : Int
  device : String
  inode : String
}

///|
pub struct EffectFileOperationReceipt {
  operation : EffectFileOperation
  evidence : EffectFileReplacementEvidence
  contract : PublicationContract
  typed_outcome_wire : String
}

///|
/// Exact selected file location and original row selector, without DATA
/// normalization. Equal digests are not physical identity or authorization.
pub fn effect_file_target_cid(
  installation_cid : String,
  directory : String,
  name : String,
  resource : String,
  row_identity_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, EffectRowOutcomeIssue] {
  if !valid_contract_cid(installation_cid) ||
    directory.is_empty() ||
    name.is_empty() ||
    name.contains("/") ||
    name == "." ||
    name == ".." ||
    directory.length() > max_wire_bytes ||
    name.length() > max_wire_bytes ||
    resource.is_empty() ||
    resource.length() > max_wire_bytes ||
    row_identity_wire.length() > max_wire_bytes {
    return Err(ForeignRow)
  }
  let row = match
    parse_contract_wire(
      row_identity_wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
      data_keys=true,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignRow)
  }
  try {
    if @json.stringify_value(row, max_wire_bytes, max_nodes, max_depth) !=
      row_identity_wire {
      return Err(ForeignRow)
    }
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    local_operation_text(writer, "backend_kind", "json_file")
    local_operation_text(writer, "directory", directory)
    local_operation_text(writer, "name", name)
    local_operation_text(writer, "installation_cid", installation_cid)
    local_operation_text(writer, "resource", resource)
    @encode.key(writer, "row_identity")
    @json.emit_value(row, writer)
    @encode.end_object(writer)
    let body = match
      parse_contract_wire(
        @encode.finish(writer),
        max_wire_bytes,
        max_nodes,
        max_depth,
        data_keys=true,
      ) {
      Ok(value) => value
      Err(_) => return Err(Encoding)
    }
    Ok(@json.cid_value(body, max_wire_bytes, max_nodes, max_depth))
  } catch {
    _ => Err(Encoding)
  }
}

///|
pub fn prepare_effect_file_operation(
  preview : EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  installation_cid : String,
  target_cid : String,
  canonical_request_cid : String,
  dispatch_entry_cid : String,
  authorization_context_cid : String,
  resolution_cid : String,
  target_version_cid : String,
) -> Result[EffectFileOperation, EffectRowOutcomeIssue] {
  for
    cid in [
      installation_cid, target_cid, canonical_request_cid, dispatch_entry_cid, authorization_context_cid,
      resolution_cid, target_version_cid,
    ] {
    if !valid_contract_cid(cid) {
      return Err(InvalidDispatch)
    }
  }
  guard effect_preview_member_kind(preview, member_index) == Some("update") &&
    effect_preview_member_identity(preview, member_index)
    is Some(member_preview_cid) &&
    effect_preview_row_identity(preview, member_index, row_index)
    is Some(row_preview_cid) &&
    effect_preview_member_source_binding_cid(preview, member_index) ==
    Some(installation_cid) &&
    effect_preview_member_authority_scope_cid(preview, member_index) ==
    Some(authorization_context_cid) &&
    effect_preview_row_guard_version_cid(preview, member_index, row_index) ==
    Some(target_version_cid) else {
    return Err(ForeignRow)
  }
  Ok({
    effect_preview_cid: effect_preview_semantic_identity(preview),
    member_preview_cid,
    row_preview_cid,
    installation_cid,
    target_cid,
    canonical_request_cid,
    dispatch_entry_cid,
    authorization_context_cid,
    resolution_cid,
    target_version_cid,
  })
}

///|
fn file_generation_word_valid(value : String) -> Bool {
  protocol_string_pattern(value, 15)
}

///|
pub fn admit_effect_file_replacement_evidence(
  replacement : Bytes,
  device : String,
  inode : String,
  generation_size : Int64,
  max_replacement_bytes : Int,
) -> Result[EffectFileReplacementEvidence, EffectRowOutcomeIssue] {
  if max_replacement_bytes < 1 ||
    replacement.length() > max_replacement_bytes ||
    !file_generation_word_valid(device) ||
    !file_generation_word_valid(inode) ||
    generation_size != replacement.length().to_int64() {
    return Err(ForeignResponse)
  }
  Ok({
    physical_sha256: @sha.hex(replacement),
    byte_count: replacement.length(),
    device,
    inode,
  })
}

///|
fn file_operation_outcome(
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@json.CanonicalValue, EffectRowOutcomeIssue] {
  let value = match
    parse_effect_outcome_shape(wire, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(issue) => return Err(Outcome(issue))
  }
  if !(@json.object_field(value, "state") is Some(@json.String("applied"))) ||
    @json.object_field(value, "action") is Some(_) {
    return Err(ForeignResponse)
  }
  Ok(value)
}

///|
/// Pure receipt DATA, not a physical ACK or an atomic file+Journal COMMIT.
/// The Host must first retain the actual original replacement ACK, then commit
/// these exact bytes with their independent Journal custody witness. An
/// uncertain replacement/append permits neither an applied claim nor a resend.
pub fn prepare_effect_file_operation_receipt(
  operation : EffectFileOperation,
  evidence : EffectFileReplacementEvidence,
  typed_outcome_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[EffectFileOperationReceipt, EffectRowOutcomeIssue] {
  let outcome = match
    file_operation_outcome(
      typed_outcome_wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let body = try {
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    for
      (name, value) in [
        ("version", "actql-local-effect-operation-receipt/0.1"),
        ("backend_kind", "json_file"),
        ("operation_kind", "update"),
        ("replacement_status", "acknowledged"),
        ("effect_preview_cid", operation.effect_preview_cid),
        ("effect_member_preview_cid", operation.member_preview_cid),
        ("row_preview_cid", operation.row_preview_cid),
        ("installation_cid", operation.installation_cid),
        ("target_cid", operation.target_cid),
        ("canonical_request_cid", operation.canonical_request_cid),
        ("dispatch_entry_cid", operation.dispatch_entry_cid),
        ("authorization_context_cid", operation.authorization_context_cid),
        ("resolution_cid", operation.resolution_cid),
        ("target_version_cid", operation.target_version_cid),
        ("replacement_physical_sha256", evidence.physical_sha256),
        (
          "typed_outcome_cid",
          @json.cid_value(outcome, max_wire_bytes, max_nodes, max_depth),
        ),
      ] {
      local_operation_text(writer, name, value)
    }
    @encode.key(writer, "replacement_byte_count")
    @encode.number_value(writer, evidence.byte_count.to_double())
    @encode.key(writer, "replacement_generation")
    @encode.begin_object(writer)
    local_operation_text(writer, "device", evidence.device)
    local_operation_text(writer, "inode", evidence.inode)
    local_operation_text(writer, "size", evidence.byte_count.to_string())
    @encode.end_object(writer)
    @encode.key(writer, "typed_outcome")
    @json.emit_value(outcome, writer)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Encoding)
  }
  let contract = match
    seal_publication_contract(
      "effect_local_operation_receipt", body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Outcome(issue))
  }
  Ok({ operation, evidence, contract, typed_outcome_wire, })
}

///|
/// Admit exact saved bytes against the original bounded replacement evidence.
/// A self-consistent receipt CID alone does not prove the bytes/generation.
pub fn admit_effect_file_operation_receipt(
  operation : EffectFileOperation,
  evidence : EffectFileReplacementEvidence,
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[EffectFileOperationReceipt, EffectRowOutcomeIssue] {
  let contract = match
    admit_publication_contract(
      "effect_local_operation_receipt", wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Outcome(issue))
  }
  guard @json.object_field(contract.value, "typed_outcome") is Some(outcome) else {
    return Err(ForeignResponse)
  }
  let outcome_wire = @json.stringify_value(
    outcome, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  let expected = match
    prepare_effect_file_operation_receipt(
      operation, evidence, outcome_wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if contract.wire != expected.contract.wire {
    return Err(ForeignResponse)
  }
  Ok(expected)
}

///|
pub fn effect_file_operation_receipt_wire(
  receipt : EffectFileOperationReceipt,
) -> String {
  receipt.contract.wire
}

///|
pub fn effect_file_operation_receipt_cid(
  receipt : EffectFileOperationReceipt,
) -> String {
  receipt.contract.identity
}

///|
pub fn issue_effect_row_outcome_receipt_from_file(
  preview : EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  dispatch_entry_cid : String,
  response : EffectFileOperationReceipt,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, EffectRowOutcomeIssue] {
  let operation = response.operation
  let expected = match
    prepare_effect_file_operation(
      preview,
      member_index,
      row_index,
      operation.installation_cid,
      operation.target_cid,
      operation.canonical_request_cid,
      dispatch_entry_cid,
      operation.authorization_context_cid,
      operation.resolution_cid,
      operation.target_version_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if operation.effect_preview_cid != expected.effect_preview_cid ||
    operation.member_preview_cid != expected.member_preview_cid ||
    operation.row_preview_cid != expected.row_preview_cid ||
    operation.dispatch_entry_cid != dispatch_entry_cid {
    return Err(ForeignRow)
  }
  let outcome = match
    file_operation_outcome(
      response.typed_outcome_wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  seal_effect_local_row_outcome(
    operation.effect_preview_cid,
    operation.member_preview_cid,
    operation.row_preview_cid,
    dispatch_entry_cid,
    response.contract,
    outcome,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
pub fn admit_effect_row_outcome_receipt_from_file(
  preview : EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  dispatch_entry_cid : String,
  response : EffectFileOperationReceipt,
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
  let expected = match
    issue_effect_row_outcome_receipt_from_file(
      preview, member_index, row_index, dispatch_entry_cid, response, max_wire_bytes,
      max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if candidate.wire != expected.wire {
    return Err(ForeignResponse)
  }
  Ok(candidate)
}

///|
/// Bounded saved response DATA only. The protected Journal must compare its
/// independent witness and original dispatch/context/Resolution; row admission
/// separately checks the original Preview. This does not recreate physical IO.
pub fn admit_saved_effect_file_operation_receipt(
  wire : String,
  replacement : Bytes,
  max_replacement_bytes : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[EffectFileOperationReceipt, EffectRowOutcomeIssue] {
  let contract = match
    admit_publication_contract(
      "effect_local_operation_receipt", wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Outcome(issue))
  }
  let value = contract.value
  fn text(value : @json.CanonicalValue, key : String) -> String? {
    match @json.object_field(value, key) {
      Some(@json.String(text)) => Some(text)
      _ => None
    }
  }
  guard text(value, "backend_kind") == Some("json_file") &&
    text(value, "effect_preview_cid") is Some(effect_preview_cid) &&
    text(value, "effect_member_preview_cid") is Some(member_preview_cid) &&
    text(value, "row_preview_cid") is Some(row_preview_cid) &&
    text(value, "installation_cid") is Some(installation_cid) &&
    text(value, "target_cid") is Some(target_cid) &&
    text(value, "canonical_request_cid") is Some(canonical_request_cid) &&
    text(value, "dispatch_entry_cid") is Some(dispatch_entry_cid) &&
    text(value, "authorization_context_cid") is Some(authorization_context_cid) &&
    text(value, "resolution_cid") is Some(resolution_cid) &&
    text(value, "target_version_cid") is Some(target_version_cid) &&
    @json.object_field(value, "replacement_generation") is Some(generation) &&
    text(generation, "device") is Some(device) &&
    text(generation, "inode") is Some(inode) &&
    text(generation, "size") == Some(replacement.length().to_string()) &&
    @json.object_field(value, "typed_outcome") is Some(outcome) else {
    return Err(ForeignResponse)
  }
  let evidence = match
    admit_effect_file_replacement_evidence(
      replacement,
      device,
      inode,
      replacement.length().to_int64(),
      max_replacement_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let count_matches = match
    @json.object_field(value, "replacement_byte_count") {
    Some(@json.Number(count)) => count == evidence.byte_count.to_double()
    _ => false
  }
  let outcome_cid = @json.cid_value(
    outcome, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  if !count_matches ||
    text(value, "replacement_physical_sha256") != Some(evidence.physical_sha256) ||
    text(value, "typed_outcome_cid") != Some(outcome_cid) {
    return Err(ForeignResponse)
  }
  let typed_outcome_wire = @json.stringify_value(
    outcome, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  let operation : EffectFileOperation = {
    effect_preview_cid,
    member_preview_cid,
    row_preview_cid,
    installation_cid,
    target_cid,
    canonical_request_cid,
    dispatch_entry_cid,
    authorization_context_cid,
    resolution_cid,
    target_version_cid,
  }
  Ok({ operation, evidence, contract, typed_outcome_wire, })
}
