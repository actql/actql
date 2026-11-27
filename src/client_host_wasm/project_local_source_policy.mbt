///|
/// A protected operator declaration for one Local CSV View. The selected
/// installation retains its exact file bytes independently of Model egress.
priv struct StoredPortableLocalSourcePolicy {
  connection : String
  resource : String
  root : String
  connectors_sha256 : String
  classification : @environment.DataClassification
}

///|
fn portable_local_source_policy_capacity(bytes : Int) -> Int64? {
  guard bytes > 0 &&
    bytes <= 8192 &&
    @decode.preserving_json_admission_construction_inventory(bytes, 7, 1)
    is Some(parser) &&
    @decode.closed_object_field_construction_extent(Some(6), 6, 0L)
    is Some(fields) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: parser.record_headers + fields.record_headers + 24L,
    reference_slots: parser.reference_slots + fields.reference_slots + 40L,
    scalar_words: parser.scalar_words + fields.scalar_words + 32L,
    // Both digest format checks and the one retained SHA result are bounded.
    owned_utf16_units: parser.owned_utf16_units + 2L * 71L,
    owned_wire_bytes: 0L,
  })
}

///|
fn valid_portable_local_source_policy_digest(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index in 7..<71 {
    let c = value.code_unit_at(index).to_int()
    if !((c >= 48 && c <= 57) || (c >= 97 && c <= 102)) {
      return false
    }
  }
  true
}

///|
fn admit_portable_local_source_policy(
  bytes : Bytes,
) -> StoredPortableLocalSourcePolicy? {
  let extent = bytes.length()
  guard extent > 0 &&
    extent <= 8192 &&
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: extent,
      max_nodes: 7,
      max_depth: 1,
    })
    is Ok(root) &&
    @decode.admit(root, {
      max_nodes: 7,
      max_depth: 1,
      max_string_bytes: extent,
      max_total_string_bytes: extent,
    })
    is Ok(cursor) &&
    @decode.closed_object(cursor, [
      "version", "connection", "resource", "root", "connectors_sha256", "data_classification",
    ])
    is Ok(fields) &&
    required_text(fields, "version") ==
    Some("actql-local-source-policy-binding/0.1") &&
    required_text(fields, "connection") is Some(connection) &&
    @scalar.admit_utf8_length(connection, 128) is Ok(_) &&
    !connection.is_empty() &&
    required_text(fields, "resource") is Some(resource) &&
    @scalar.admit_utf8_length(resource, 255) is Ok(_) &&
    !resource.is_empty() &&
    required_text(fields, "root") is Some(root) &&
    root.has_prefix("/") &&
    @scalar.admit_utf8_length(root, 4096) is Ok(_) &&
    required_text(fields, "connectors_sha256") is Some(connectors_sha256) &&
    valid_portable_local_source_policy_digest(connectors_sha256) else {
    return None
  }
  let classification : @environment.DataClassification = match
    required_text(fields, "data_classification") {
    Some("public") => Public
    Some("internal") => Internal
    Some("confidential") => Confidential
    Some("restricted") => Restricted
    _ => return None
  }
  Some({ connection, resource, root, connectors_sha256, classification, })
}
