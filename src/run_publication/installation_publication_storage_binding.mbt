///|
/// Closed storage-association DATA for installation publication. Even a valid
/// value does not attest a metadata observation, admit a Store, authenticate a
/// cold generation, issue a Credential use or reserve physical capacity. The
/// existing Host must obtain these fields from its exact live Store original.
struct InstallationPublicationStorageBinding {
  wire : String
  identity : String
  store_authority_cid : String
  key_generation_cid : String
}

///|
/// Package the original Store projection without borrowing a Run's evidence
/// purpose. Limits bound the codec, not the physical overlapping holdings.
pub fn prepare_installation_publication_storage_binding(
  store_contract_wire : String,
  store_authority_cid : String,
  key_generation_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[InstallationPublicationStorageBinding, PublicationContractIssue] {
  if max_wire_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(InvalidLimits)
  }
  if !valid_contract_cid(store_authority_cid) ||
    !valid_contract_cid(key_generation_cid) ||
    store_contract_wire.length() > max_wire_bytes {
    return Err(InvalidField("installation_publication_storage_binding"))
  }
  let expected = "{\"version\":\"actql-local-publication-store/0.1\",\"isolation\":\"execution-namespace\",\"store_authority_cid\":\"" +
    store_authority_cid +
    "\"}"
  if store_contract_wire != expected {
    return Err(InvalidField("store_contract_wire"))
  }
  let wire = try {
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_ordered_object(writer)
    for
      (key, value) in [
        ("key_generation_cid", key_generation_cid),
        ("private_namespace", "publication-private"),
        ("store_authority_cid", store_authority_cid),
        ("store_contract_wire", store_contract_wire),
        ("version", "actql-installation-publication-storage-binding/0.1"),
      ] {
      @encode.ordered_key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Encoding)
  }
  let digest = match @sha.text_hex(wire) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  Ok({
    wire,
    identity: "sha256:" + digest,
    store_authority_cid,
    key_generation_cid,
  })
}

///|
/// Re-admit exact canonical DATA. The expected CID must be independently
/// selected by the consuming Owner; agreement here is not physical custody.
pub fn read_installation_publication_storage_binding(
  wire : String,
  expected_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[InstallationPublicationStorageBinding, PublicationContractIssue] {
  // Reject the code-unit lower bound before allocating the preserving UTF-8
  // input. The full parser/Writer still checks exact bytes, nodes and depth.
  if max_wire_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(InvalidLimits)
  }
  if wire.length() > max_wire_bytes || !valid_contract_cid(expected_cid) {
    return Err(InvalidWire)
  }
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
      "installation_publication_storage_binding", value, true, max_wire_bytes, max_nodes,
      max_depth,
    ) {
    return Err(InvalidField("installation_publication_storage_binding"))
  }
  guard contract_string_from_value(value, "store_contract_wire")
    is Some(contract) &&
    contract_string_from_value(value, "store_authority_cid") is Some(authority) &&
    contract_string_from_value(value, "key_generation_cid") is Some(generation) else {
    return Err(InvalidObject)
  }
  let original = match
    prepare_installation_publication_storage_binding(
      contract, authority, generation, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if original.wire != wire {
    return Err(InvalidWire)
  }
  if original.identity != expected_cid {
    return Err(IdentityMismatch)
  }
  Ok(original)
}

///|
pub fn installation_publication_storage_binding_wire(
  value : InstallationPublicationStorageBinding,
) -> String {
  value.wire
}

///|
pub fn installation_publication_storage_binding_cid(
  value : InstallationPublicationStorageBinding,
) -> String {
  value.identity
}

///|
/// DATA comparison only. Neither equality nor this projection issues authority.
pub fn installation_publication_storage_binding_fields(
  value : InstallationPublicationStorageBinding,
) -> (String, String) {
  (value.store_authority_cid, value.key_generation_cid)
}
