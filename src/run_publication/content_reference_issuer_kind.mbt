///|
/// Strict DATA classification before selecting a stored-content inverse. The
/// complete closed envelope, both self CIDs and canonical wire are rebuilt by
/// the same owner as candidate admission. This grants no Reference authority.
pub fn recovered_content_issuer_kind(
  original_wire : String,
  limits : @admitted.ReferenceLimits,
) -> Result[String, GeneratedContentReferenceIssue] {
  let original = match
    parse_contract_wire(
      original_wire,
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
      data_keys=true,
    ) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  guard @json.object_field(original, "metadata") is Some(metadata) &&
    @json.object_field(metadata, "issuer_evidence") is Some(evidence) &&
    contract_string_from_value(evidence, "issuer_kind") is Some(kind) &&
    (kind == "connector_capture" || kind == "content_derivation") else {
    return Err(InvalidBinding("issuer_kind"))
  }
  let expires_at = match @json.object_field(metadata, "expires_at") {
    None => None
    Some(@json.String(time)) => Some(time)
    _ => return Err(InvalidBinding("expires_at"))
  }
  guard contract_string_from_value(metadata, "content_store_id")
    is Some(content_store_id) &&
    contract_string_from_value(evidence, "content_store_cid")
    is Some(content_store_cid) &&
    contract_string_from_value(evidence, "workspace_scope_cid")
    is Some(workspace_scope_cid) &&
    contract_string_from_value(metadata, "storage_scope") is Some(storage_scope) &&
    contract_string_from_value(metadata, "retention_class")
    is Some(retention_class) &&
    contract_string_from_value(metadata, "availability_evidence_cid")
    is Some(availability_evidence_cid) &&
    contract_string_from_value(metadata, "effective_data_policy_cid")
    is Some(effective_data_policy_cid) &&
    contract_string_from_value(metadata, "data_classification")
    is Some(data_classification) &&
    contract_string_from_value(evidence, "issuer_contract_cid")
    is Some(issuer_contract_cid) &&
    contract_string_from_value(evidence, "capture_authority_cid")
    is Some(capture_authority_cid) else {
    return Err(InvalidBinding("binding"))
  }
  let binding : GeneratedContentBinding = {
    content_store_id,
    content_store_cid,
    workspace_scope_cid,
    storage_scope,
    retention_class,
    expires_at,
    availability_evidence_cid,
    effective_data_policy_cid,
    data_classification,
    issuer_contract_cid,
    capture_authority_cid,
  }
  match stored_content_reference_parts(original_wire, binding, kind, limits) {
    Err(issue) => Err(issue)
    Ok(_) =>
      if kind == "connector_capture" {
        Ok("connector_capture")
      } else {
        Ok("content_derivation")
      }
  }
}
