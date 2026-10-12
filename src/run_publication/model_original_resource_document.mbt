///|
// Data only: closed shape and exact embedded Writer bytes, not authenticated
// origin, Store acknowledgement, a current cut, restored resources or send.
// The original caller funds the parse tree, validation/hash frames and output
// overlap before entry. Codec limits are not a physical bootstrap profile.
struct ModelOriginalResourceDocument {
  value : @json.CanonicalValue
}

///|
pub fn read_model_original_resource_document(
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ModelOriginalResourceDocument, PublicationContractIssue] {
  let value = match
    parse_contract_wire(
      wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
      data_keys=true,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !validate_generated_protocol_shape(
      "model_original_resource_state", value, true, max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(InvalidField("model_original_resource_state"))
  }
  // The owned artifact uses the existing data-preserving canonical JSON path.
  // Canonical outer bytes also require canonical embedded resource bytes;
  // do not accept a whitespace/escape rewrite by hashing a different record.
  let canonical = @json.stringify_value(
    value, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  if canonical != wire {
    return Err(InvalidWire)
  }
  guard @json.object_field(value, "resource_state") is Some(state) else {
    return Err(InvalidField("resource_state"))
  }
  let identity = @json.cid_value(state, max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  if contract_string_from_value(value, "resource_state_cid") != Some(identity) {
    return Err(InvalidField("resource_state_cid"))
  }
  Ok({ value, })
}

///|
// Borrowed data fields for the existing checked original Owner's typed guard.
// Even all twelve matching strings would not establish physical Store custody
// or a stable current cut. No Ledger/token/permission getter exists here.
pub fn model_original_resource_origin_field(
  document : ModelOriginalResourceDocument,
  field : String,
) -> String? {
  guard @json.object_field(document.value, "origin") is Some(origin) else {
    return None
  }
  contract_string_from_value(origin, field)
}

///|
// Extract only the original preparation-base payload from the already checked
// canonical envelope. The exact embedded bytes/CID were checked on admission;
// this is data, not a current-cut, Store ACK or restoration capability.
// The existing caller funds canonical traversal, output text and Reader overlap
// before entry. These codec ceilings do not establish that physical budget.
pub fn model_original_preparation_resource_wire(
  document : ModelOriginalResourceDocument,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, PublicationContractIssue] {
  if max_bytes < 0 || max_nodes < 1 || max_depth < 0 {
    return Err(InvalidField("resource_state"))
  }
  if contract_string_from_value(document.value, "resource_phase") !=
    Some("preparation_base") ||
    !(@json.object_field(document.value, "cut") is Some(@json.Null)) {
    return Err(InvalidField("resource_phase"))
  }
  guard @json.object_field(document.value, "resource_state") is Some(state) else {
    return Err(InvalidField("resource_state"))
  }
  let wire = @json.stringify_value(state, max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  Ok(wire)
}
