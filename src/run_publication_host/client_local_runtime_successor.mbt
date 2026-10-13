///|
/// Pure closed metadata for one explicit runtime successor. This is not an
/// authenticated installation original, product witness, compatibility proof,
/// current permission, grant, start claim or a replacement old Run material.
struct ClientLocalRuntimeSuccessorMetadata {
  body : Bytes
  fields : Array[String]
}

///|
pub(all) enum ClientLocalRuntimeSuccessorIssue {
  InvalidOriginal
  CapacityExceeded
  Encoding
} derive(Eq, Debug)

///|
fn local_runtime_successor_keys() -> Array[String] {
  [
    "account_configuration_cid", "adoption_cid", "authority_scope_cid",
    "current_package_identity_wire", "operation_id", "original_upgrade_cid",
    "original_upgrade_packet_sha256", "prior_pair_sha256", "prior_runtime_wire",
    "successor_runtime_pair_wire", "version",
  ]
}

///|
fn local_runtime_successor_fields_valid(fields : Array[String]) -> Bool {
  if fields.length() != 11 ||
    fields[10] != "actql-local-runtime-successor/0.1" ||
    fields[4].is_empty() ||
    fields[4].length() > 128 ||
    fields[4].contains("\u{0000}") {
    return false
  }
  for index in [0, 1, 2, 5] {
    if !fields[index].has_prefix("sha256:") ||
      !runtime_hex(fields[index].substring(start=7), 64) {
      return false
    }
  }
  if ![6, 7].all(index => runtime_hex(fields[index], 64)) {
    return false
  }
  [3, 8, 9].all(index => {
    !fields[index].is_empty() && fields[index].length() <= 4096
  })
}

///|
fn local_runtime_successor_encode(
  fields : Array[String],
) -> Result[ClientLocalRuntimeSuccessorMetadata, ClientLocalRuntimeSuccessorIssue] {
  if !local_runtime_successor_fields_valid(fields) {
    return Err(InvalidOriginal)
  }
  // A lower bound only, never workspace admission. It rejects definitely
  // oversized material before the bounded codec copies/escapes its values.
  let keys = local_runtime_successor_keys()
  let mut minimum = 2 + fields.length() - 1
  for index, key in keys {
    minimum += key.length() + fields[index].length() + 5
  }
  if minimum > 5632 {
    return Err(CapacityExceeded)
  }
  let body = match
    client_local_original_record_body(keys.mapi((index, key) => {
      (key, fields[index])
    })) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  if body.length() > 5632 {
    return Err(CapacityExceeded)
  }
  // Enforce the existing 4096-byte string and aggregate/tree limits as well;
  // UTF16 length alone is not encoded-byte or memory capacity evidence.
  let checked = match client_local_original_record_fields(body, keys) {
    Ok(value) => value
    Err(_) => return Err(InvalidOriginal)
  }
  Ok({ body, fields: checked, })
}

///|
/// Encode literal metadata only. Native must obtain the old/current inputs
/// from their actual Owners, reserve before copying, authenticate both linked
/// rows and commit one append/counter in the original transaction separately.
pub fn client_local_runtime_successor_metadata(
  account_configuration_cid : String,
  adoption_cid : String,
  authority_scope_cid : String,
  current_package_identity_wire : String,
  operation_id : String,
  original_upgrade_cid : String,
  original_upgrade_packet_sha256 : String,
  prior_pair_sha256 : String,
  prior_runtime_wire : String,
  successor_runtime_pair_wire : String,
) -> Result[ClientLocalRuntimeSuccessorMetadata, ClientLocalRuntimeSuccessorIssue] {
  local_runtime_successor_encode([
    account_configuration_cid, adoption_cid, authority_scope_cid,
    current_package_identity_wire, operation_id, original_upgrade_cid,
    original_upgrade_packet_sha256, prior_pair_sha256, prior_runtime_wire,
    successor_runtime_pair_wire, "actql-local-runtime-successor/0.1",
  ])
}

///|
/// Parse the original closed body with unchanged Local record limits. This
/// deliberately does not turn copied metadata/CIDs into opaque physical facts.
pub fn read_client_local_runtime_successor_metadata(
  body : Bytes,
) -> Result[ClientLocalRuntimeSuccessorMetadata, ClientLocalRuntimeSuccessorIssue] {
  if body.length() > 5632 {
    return Err(CapacityExceeded)
  }
  let fields = match
    client_local_original_record_fields(body, local_runtime_successor_keys()) {
    Ok(value) => value
    Err(_) => return Err(InvalidOriginal)
  }
  if !local_runtime_successor_fields_valid(fields) {
    return Err(InvalidOriginal)
  }
  Ok({ body, fields, })
}

///|
pub fn client_local_runtime_successor_metadata_body(
  value : ClientLocalRuntimeSuccessorMetadata,
) -> Bytes {
  value.body
}

///|
/// Content identity only, never an HMAC/custody/current or compatibility fact.
pub fn client_local_runtime_successor_metadata_cid(
  value : ClientLocalRuntimeSuccessorMetadata,
) -> String {
  "sha256:" + @sha.hex(value.body)
}

///|
/// Borrow one literal field without exposing or copying an owned array.
pub fn client_local_runtime_successor_metadata_field(
  value : ClientLocalRuntimeSuccessorMetadata,
  key : String,
) -> String? {
  for index, original in local_runtime_successor_keys() {
    if original == key {
      return Some(value.fields[index])
    }
  }
  None
}
