///|
/// Original local-operation binding DATA. The constructor checks the admitted
/// Preview row; only the installed backend can establish current permission,
/// the dispatch claim and durable receipt custody. This is not a send permit.
pub struct EffectLocalOperation {
  effect_preview_cid : String
  member_preview_cid : String
  row_preview_cid : String
  backend_kind : String
  installation_cid : String
  target_cid : String
  canonical_request_cid : String
  dispatch_entry_cid : String
  authorization_use_cid : String
  approval_use_cid : String
  target_version_cid : String
}

///|
pub(all) enum EffectLocalOperationResult {
  Applied(String)
  Conflict(String?)
} derive(Eq, Debug)

///|
/// This pure value is not a COMMIT acknowledgment. Its backend must atomically
/// retain these bytes with the conditional mutation, then verify the original
/// durable readback before using it as saved local response evidence.
pub struct EffectLocalOperationReceipt {
  operation : EffectLocalOperation
  result : EffectLocalOperationResult
  contract : PublicationContract
  typed_outcome_wire : String
}

///|
fn local_operation_text(
  writer : @encode.Writer,
  name : String,
  value : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.key(writer, name)
  @encode.string_value(writer, value)
}

///|
/// Exact private installation bytes, including registration, revision, Mapping
/// and primary identity. Neither this digest nor equal configuration is authority.
pub fn effect_local_installation_cid(
  configuration_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, EffectRowOutcomeIssue] {
  if configuration_wire.length() > max_wire_bytes {
    return Err(ForeignResponse)
  }
  match
    parse_contract_wire(
      configuration_wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
      data_keys=true,
    ) {
    Ok(value) if @json.object_field_count(value) is Some(_) =>
      Ok("sha256:" + @sha.hex(@utf8.encode(configuration_wire)))
    _ => Err(ForeignResponse)
  }
}

///|
/// Preserve the original resource and row selector. This closed fingerprint
/// joins physical backend lookup to a prepared binding; it grants no access.
pub fn effect_local_target_cid(
  installation_cid : String,
  resource : String,
  row_identity_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, EffectRowOutcomeIssue] {
  if !valid_contract_cid(installation_cid) ||
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
    local_operation_text(writer, "backend_kind", "sqlite")
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
/// Bind only the existing local UPDATE row. CID inputs record actual use and
/// installation facts supplied by the trusted Host, not newly issued grants.
pub fn prepare_effect_local_operation(
  preview : EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  installation_cid : String,
  target_cid : String,
  canonical_request_cid : String,
  dispatch_entry_cid : String,
  authorization_use_cid : String,
  approval_use_cid : String,
  target_version_cid : String,
) -> Result[EffectLocalOperation, EffectRowOutcomeIssue] {
  for
    cid in [
      installation_cid, target_cid, canonical_request_cid, dispatch_entry_cid, authorization_use_cid,
      approval_use_cid, target_version_cid,
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
    effect_preview_row_guard_version_cid(preview, member_index, row_index) ==
    Some(target_version_cid) else {
    return Err(ForeignRow)
  }
  Ok({
    effect_preview_cid: effect_preview_semantic_identity(preview),
    member_preview_cid,
    row_preview_cid,
    backend_kind: "sqlite",
    installation_cid,
    target_cid,
    canonical_request_cid,
    dispatch_entry_cid,
    authorization_use_cid,
    approval_use_cid,
    target_version_cid,
  })
}

///|
fn local_operation_outcome(
  result : EffectLocalOperationResult,
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
  match result {
    Applied(version) =>
      if !valid_contract_cid(version) ||
        !(@json.object_field(value, "state") is Some(@json.String("applied"))) ||
        @json.object_field(value, "action") is Some(_) {
        return Err(ForeignResponse)
      }
    Conflict(version) => {
      if version is Some(cid) && !valid_contract_cid(cid) {
        return Err(ForeignResponse)
      }
      guard @json.object_field(value, "state") is Some(@json.String("failed")) &&
        @json.object_field(value, "error") is Some(error) &&
        @json.object_field(error, "code") is Some(@json.String("conflict")) else {
        return Err(ForeignResponse)
      }
    }
  }
  Ok(value)
}

///|
/// Prepare DATA inside the original backend transaction. No successful return
/// establishes COMMIT, physical ACK, permission or terminal Journal state.
pub fn prepare_effect_local_operation_receipt(
  operation : EffectLocalOperation,
  result : EffectLocalOperationResult,
  typed_outcome_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[EffectLocalOperationReceipt, EffectRowOutcomeIssue] {
  let outcome = match
    local_operation_outcome(
      result, typed_outcome_wire, max_wire_bytes, max_nodes, max_depth,
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
        ("effect_preview_cid", operation.effect_preview_cid),
        ("effect_member_preview_cid", operation.member_preview_cid),
        ("row_preview_cid", operation.row_preview_cid),
        ("backend_kind", operation.backend_kind),
        ("installation_cid", operation.installation_cid),
        ("target_cid", operation.target_cid),
        ("operation_kind", "update"),
        ("canonical_request_cid", operation.canonical_request_cid),
        ("dispatch_entry_cid", operation.dispatch_entry_cid),
        ("authorization_use_cid", operation.authorization_use_cid),
        ("approval_use_cid", operation.approval_use_cid),
        ("target_version_cid", operation.target_version_cid),
      ] {
      local_operation_text(writer, name, value)
    }
    local_operation_text(
      writer,
      "commit_status",
      match result {
        Applied(_) => "committed"
        Conflict(_) => "conflict"
      },
    )
    @encode.key(writer, "observed_version_cid")
    match result {
      Applied(version) | Conflict(Some(version)) =>
        @encode.string_value(writer, version)
      Conflict(None) => @encode.null_value(writer)
    }
    @encode.key(writer, "typed_outcome")
    @json.emit_value(outcome, writer)
    local_operation_text(
      writer,
      "typed_outcome_cid",
      @json.cid_value(outcome, max_wire_bytes, max_nodes, max_depth),
    )
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
  let typed_outcome_wire = @json.stringify_value(
    outcome, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  Ok({ operation, result, contract, typed_outcome_wire, })
}

///|
/// Re-admit only bytes read from the same original backend operation. Content
/// admission cannot establish transaction custody; the backend retains that duty.
pub fn admit_effect_local_operation_receipt(
  operation : EffectLocalOperation,
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[EffectLocalOperationReceipt, EffectRowOutcomeIssue] {
  let contract = match
    admit_publication_contract(
      "effect_local_operation_receipt", wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Outcome(issue))
  }
  let value = contract.value
  let version = match @json.object_field(value, "observed_version_cid") {
    Some(@json.String(cid)) => Some(cid)
    Some(@json.Null) => None
    _ => return Err(ForeignResponse)
  }
  let result = match @json.object_field(value, "commit_status") {
    Some(@json.String("committed")) =>
      match version {
        Some(cid) => Applied(cid)
        None => return Err(ForeignResponse)
      }
    Some(@json.String("conflict")) => Conflict(version)
    _ => return Err(ForeignResponse)
  }
  guard @json.object_field(value, "typed_outcome") is Some(outcome) else {
    return Err(ForeignResponse)
  }
  let outcome_wire = @json.stringify_value(
    outcome, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  let expected = match
    prepare_effect_local_operation_receipt(
      operation, result, outcome_wire, max_wire_bytes, max_nodes, max_depth,
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
pub fn effect_local_operation_receipt_wire(
  receipt : EffectLocalOperationReceipt,
) -> String {
  receipt.contract.wire
}

///|
pub fn effect_local_operation_receipt_cid(
  receipt : EffectLocalOperationReceipt,
) -> String {
  receipt.contract.identity
}

///|
/// Seal the same row outcome around its actual local operation receipt.
/// The byte digest addresses complete local receipt bytes, never HTTP data.
pub fn issue_effect_row_outcome_receipt_from_local(
  preview : EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  dispatch_entry_cid : String,
  response : EffectLocalOperationReceipt,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, EffectRowOutcomeIssue] {
  let operation = response.operation
  if operation.effect_preview_cid != effect_preview_semantic_identity(preview) ||
    Some(operation.member_preview_cid) !=
    effect_preview_member_identity(preview, member_index) ||
    Some(operation.row_preview_cid) !=
    effect_preview_row_identity(preview, member_index, row_index) ||
    Some(operation.target_version_cid) !=
    effect_preview_row_guard_version_cid(preview, member_index, row_index) ||
    effect_preview_member_kind(preview, member_index) != Some("update") ||
    operation.dispatch_entry_cid != dispatch_entry_cid {
    return Err(ForeignRow)
  }
  let outcome = match
    local_operation_outcome(
      response.result,
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
/// One unchanged local row-receipt preimage for SQLite and file observations.
fn seal_effect_local_row_outcome(
  effect_preview_cid : String,
  member_preview_cid : String,
  row_preview_cid : String,
  dispatch_entry_cid : String,
  response : PublicationContract,
  outcome : @json.CanonicalValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, EffectRowOutcomeIssue] {
  let bytes = @utf8.encode(response.wire)
  let body = try {
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    for
      (name, value) in [
        ("version", "actql-effect-row-outcome-receipt/0.1"),
        ("effect_preview_cid", effect_preview_cid),
        ("effect_member_preview_cid", member_preview_cid),
        ("row_preview_cid", row_preview_cid),
        ("dispatch_entry_cid", dispatch_entry_cid),
        ("response_kind", "local_operation"),
        ("local_operation_receipt_cid", response.identity),
        ("response_physical_sha256", @sha.hex(bytes)),
        (
          "typed_outcome_cid",
          @json.cid_value(outcome, max_wire_bytes, max_nodes, max_depth),
        ),
      ] {
      local_operation_text(writer, name, value)
    }
    @encode.key(writer, "response_byte_count")
    @encode.number_value(writer, bytes.length().to_double())
    @encode.key(writer, "typed_outcome")
    @json.emit_value(outcome, writer)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Encoding)
  }
  seal_publication_contract(
    "effect_row_outcome_receipt", body, max_wire_bytes, max_nodes, max_depth,
  ).map_err(issue => Outcome(issue))
}

///|
pub fn admit_effect_row_outcome_receipt_from_local(
  preview : EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  dispatch_entry_cid : String,
  response : EffectLocalOperationReceipt,
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
    issue_effect_row_outcome_receipt_from_local(
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
