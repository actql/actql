///|
// Private transport observations are not Catalog/projection or Effect outcomes.
// Only the existing typed preparation grant/use can supply the original scope.
priv struct LocalPreparationRawBinding {
  fields : Array[String]
  descriptor_wire : String
  holding : String
  response_limit : Int
  max_plaintext_bytes : Int
}

///|
fn raw_observation_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for ch in value[7:] {
    if !((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f')) {
      return false
    }
  }
  true
}

///|
fn raw_observation_strings(
  fields : Array[String],
  max_bytes : Int,
) -> Result[String, NativePublicationStoreIssue] {
  try {
    let writer = @encode.writer(max_bytes, 16, 2)
    @encode.begin_array(writer)
    for field in fields {
      @encode.string_value(writer, field)
    }
    @encode.end_array(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidConfiguration)
  }
}

///|
fn raw_base64_bytes(bytes : Int64) -> Int64 {
  4L * ((bytes + 2L) / 3L)
}

///|
// AES-GCM's existing envelope has fixed version/nonce/tag punctuation and a
// base64 ciphertext. This accounts for that exact representation, not a cap.
fn raw_cipher_envelope_bytes(plaintext_bytes : Int64) -> Int64 {
  128L + raw_base64_bytes(plaintext_bytes)
}

///|
fn local_preparation_raw_binding(
  grant : @credential.LocalPreparationCredentialGrant,
  original_use : @credential.LocalPreparationCredentialUse,
  authority : String,
  response_limit : Int64,
) -> Result[LocalPreparationRawBinding, NativePublicationStoreIssue] {
  guard raw_observation_cid(authority) &&
    response_limit >= 0L &&
    response_limit <= 1048576L else {
    return Err(InvalidConfiguration)
  }
  let grant_cid = @credential.local_preparation_credential_grant_cid(grant)
  let use_cid = @credential.local_preparation_credential_use_cid(original_use)
  let (use_grant, _, _) = @credential.local_preparation_credential_use_projection(
    original_use,
  )
  if use_grant != grant_cid {
    return Err(StateCollision)
  }
  let grant_wire = match
    @credential.local_preparation_credential_grant_json(grant) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  let use_wire = match
    @credential.local_preparation_credential_use_json(original_use) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  // Re-admit against this exact grant, without applying a fresh lifetime or
  // ordinal. The original response remains evidence after the grant expires.
  if @credential.admit_local_preparation_credential_use_json(
      grant, use_wire, use_cid,
    )
    is Err(_) {
    return Err(StateCollision)
  }
  let fields = [
    "actql-native-local-preparation-raw-response/0.1", authority, grant_cid, use_cid,
    grant_wire, use_wire,
  ]
  let binding_wire = match raw_observation_strings(fields, 1048576) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let descriptor_fields = fields.map(value => value)
  descriptor_fields.push(response_limit.to_string())
  let descriptor_wire = match
    raw_observation_strings(descriptor_fields, 1048576) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let empty_fields = descriptor_fields.map(value => value)
  empty_fields.push("2147483647")
  empty_fields.push("sha256:" + "0".repeat(64))
  empty_fields.push("")
  let empty_wire = match raw_observation_strings(empty_fields, 1048576) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let max_plaintext_bytes = @utf8.encode(empty_wire).length().to_int64() +
    raw_base64_bytes(response_limit)
  if max_plaintext_bytes > 1048576L {
    return Err(InvalidConfiguration)
  }
  Ok({
    fields,
    descriptor_wire,
    holding: "sha256:" + @sha.hex(@utf8.encode(binding_wire)),
    response_limit: response_limit.to_int(),
    max_plaintext_bytes: max_plaintext_bytes.to_int(),
  })
}

///|
fn local_preparation_raw_reservation_bytes(
  binding : LocalPreparationRawBinding,
) -> Result[Int64, NativePublicationStoreIssue] {
  Ok(
    raw_cipher_envelope_bytes(
      @utf8.encode(binding.descriptor_wire).length().to_int64(),
    ) +
    raw_cipher_envelope_bytes(binding.max_plaintext_bytes.to_int64()),
  )
}

///|
fn local_preparation_raw_record(
  binding : LocalPreparationRawBinding,
  status : Int,
  body : Bytes,
) -> Result[String, NativePublicationStoreIssue] {
  if status < 0 || body.length() > binding.response_limit {
    return Err(InvalidConfiguration)
  }
  let fields = binding.fields.map(value => value)
  fields.push(binding.response_limit.to_string())
  fields.push(status.to_string())
  fields.push("sha256:" + @sha.hex(body))
  fields.push(@base64.encode(body))
  raw_observation_strings(fields, binding.max_plaintext_bytes)
}

///|
fn restore_local_preparation_raw_record(
  wire : String,
  binding : LocalPreparationRawBinding,
) -> Result[NativeLocalPreparationRawObservation, NativePublicationStoreIssue] {
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: binding.max_plaintext_bytes,
      max_nodes: 16,
      max_depth: 2,
    }) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: 16,
      max_depth: 2,
      max_string_bytes: binding.max_plaintext_bytes,
      max_total_string_bytes: binding.max_plaintext_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  let elements = match @decode.elements(cursor) {
    Ok(value) if value.length() == 10 => value
    _ => return Err(StateCollision)
  }
  let fields : Array[String] = []
  for element in elements {
    match @decode.text(element) {
      Ok(value) => fields.push(value)
      Err(_) => return Err(StateCollision)
    }
  }
  for index in 0..<binding.fields.length() {
    if fields[index] != binding.fields[index] {
      return Err(StateCollision)
    }
  }
  if fields[6] != binding.response_limit.to_string() {
    return Err(StateCollision)
  }
  let status = @string.parse_int(fields[7]) catch {
    _ => return Err(StateCollision)
  }
  let body = @base64.decode(fields[9][:]) catch {
    _ => return Err(StateCollision)
  }
  if status < 0 ||
    body.length() > binding.response_limit ||
    @base64.encode(body) != fields[9] ||
    "sha256:" + @sha.hex(body) != fields[8] {
    return Err(StateCollision)
  }
  match local_preparation_raw_record(binding, status, body) {
    Ok(original) if original == wire =>
      Ok({ use_cid: fields[3], status, body, body_digest: fields[8], })
    _ => Err(StateCollision)
  }
}

///|
fn local_raw_closed_strings(
  wire : String,
  max_bytes : Int,
  count : Int,
) -> Result[Array[String], NativePublicationStoreIssue] {
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: max_bytes,
      max_nodes: 16,
      max_depth: 2,
    }) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: 16,
      max_depth: 2,
      max_string_bytes: max_bytes,
      max_total_string_bytes: max_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  let elements = match @decode.elements(cursor) {
    Ok(value) if value.length() == count => value
    _ => return Err(StateCollision)
  }
  let fields : Array[String] = []
  for element in elements {
    match @decode.text(element) {
      Ok(value) => fields.push(value)
      Err(_) => return Err(StateCollision)
    }
  }
  match raw_observation_strings(fields, max_bytes) {
    Ok(original) if original == wire => Ok(fields)
    _ => Err(StateCollision)
  }
}
