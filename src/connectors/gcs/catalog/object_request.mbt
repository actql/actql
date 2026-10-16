// Exact request material, not a credential, approval, durable send claim or
// new execution owner. The existing Effect/credential owners retain those.

///|
pub(all) enum ObjectMutationKind {
  PatchMetadata
  DeleteObject
} derive(Eq, Debug)

///|
pub(all) enum ObjectRequestIssue {
  InvalidBinding
  InvalidChanges
  ReservedMetadata
  ForeignBinding
  StaleObservation
  CapacityExceeded
} derive(Eq, Debug)

///|
pub(all) struct ObjectRequestLimits {
  metadata : ObjectMetadataLimits
  max_path_bytes : Int
  max_body_bytes : Int
  max_identity_bytes : Int
}

///|
pub struct ObjectMutationBinding {
  kind : ObjectMutationKind
  bucket : String
  prefix : String
  catalog_cid : String
  installation_cid : String
  contract_cid : String
  permissions : Array[String]
  limits : ObjectRequestLimits
}

///|
pub struct ObjectMutationRequest {
  binding : ObjectMutationBinding
  original : ObjectMetadata
  method : String
  path : String
  body : String
  cid : String
}

///|
fn mutation_cid(value : String) -> Bool {
  value.length() == 71 &&
  value.has_prefix("sha256:") &&
  value[7:]
  .iter()
  .all(character => {
    (character >= '0' && character <= '9') ||
    (character >= 'a' && character <= 'f')
  })
}

///|
// The installation supplies these original bindings after common admission.
// This pure constructor checks/copies DATA and cannot issue a permission.
pub fn prepare_object_mutation_binding(
  kind : ObjectMutationKind,
  bucket : String,
  prefix : String,
  catalog_cid : String,
  installation_cid : String,
  contract_cid : String,
  permissions : Array[String],
  limits : ObjectRequestLimits,
) -> Result[ObjectMutationBinding, ObjectRequestIssue] {
  if bucket.is_empty() ||
    @scalar.admit_utf8_length(bucket, 222) is Err(_) ||
    @scalar.admit_utf8_length(prefix, 1024) is Err(_) ||
    !mutation_cid(catalog_cid) ||
    !mutation_cid(installation_cid) ||
    !mutation_cid(contract_cid) ||
    limits.metadata.max_bytes < 1 ||
    limits.metadata.max_nodes < 1 ||
    limits.metadata.max_depth < 1 ||
    limits.metadata.max_metadata_entries < 0 ||
    limits.max_path_bytes < 1 ||
    limits.max_body_bytes < 1 ||
    limits.max_identity_bytes < 1 ||
    permissions.is_empty() ||
    permissions.length() > 64 {
    return Err(InvalidBinding)
  }
  let owned = permissions.copy()
  owned.sort()
  for index in 0..<owned.length() {
    if owned[index].is_empty() ||
      @scalar.admit_utf8_length(owned[index], 256) is Err(_) ||
      (index > 0 && owned[index - 1] == owned[index]) {
      return Err(InvalidBinding)
    }
  }
  Ok({
    kind,
    bucket,
    prefix,
    catalog_cid,
    installation_cid,
    contract_cid,
    permissions: owned,
    limits,
  })
}

///|
fn mutation_part(
  value : String,
  maximum : Int,
) -> Result[String, ObjectRequestIssue] {
  if @scalar.admit_utf8_length(value, maximum) is Err(_) {
    return Err(CapacityExceeded)
  }
  let output = StringBuilder()
  let hex = "0123456789ABCDEF"
  let mut length = 0
  // Encode the exact admitted object data, without NFC or path normalization.
  for byte in @utf8.encode(value) {
    let n = byte.to_int()
    let unreserved = (n >= 65 && n <= 90) ||
      (n >= 97 && n <= 122) ||
      (n >= 48 && n <= 57) ||
      n == 45 ||
      n == 46 ||
      n == 95 ||
      n == 126
    let charge = if unreserved { 1 } else { 3 }
    if charge > maximum - length {
      return Err(CapacityExceeded)
    }
    length += charge
    if unreserved {
      output.write_char(n.to_char().unwrap())
    } else {
      output.write_char('%')
      output.write_char(hex[n >> 4].to_int().to_char().unwrap())
      output.write_char(hex[n & 15].to_int().to_char().unwrap())
    }
  }
  Ok(output.to_string())
}

///|
fn mutation_json(
  value : Json,
  maximum : Int,
  limits : ObjectMetadataLimits,
) -> Result[String, ObjectRequestIssue] {
  try {
    let value = @canonical.from_json(
      value,
      limits.max_nodes,
      limits.max_depth,
      maximum,
      data_keys=true,
    )
    Ok(
      @canonical.stringify_value(
        value,
        maximum,
        limits.max_nodes,
        limits.max_depth,
      ),
    )
  } catch {
    _ => Err(CapacityExceeded)
  }
}

///|
fn mutation_path(
  binding : ObjectMutationBinding,
  original : ObjectMetadata,
) -> Result[String, ObjectRequestIssue] {
  let fields = original.fields
  if fields.bucket != binding.bucket || !fields.name.has_prefix(binding.prefix) {
    return Err(StaleObservation)
  }
  let bucket = match
    mutation_part(binding.bucket, binding.limits.max_path_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let name = match mutation_part(fields.name, binding.limits.max_path_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let path = "/storage/v1/b/" +
    bucket +
    "/o/" +
    name +
    "?generation=" +
    fields.generation.to_string() +
    "&ifGenerationMatch=" +
    fields.generation.to_string() +
    "&ifMetagenerationMatch=" +
    fields.metageneration.to_string()
  if @scalar.admit_utf8_length(path, binding.limits.max_path_bytes) is Err(_) {
    return Err(CapacityExceeded)
  }
  Ok(path)
}

///|
fn mutation_request(
  binding : ObjectMutationBinding,
  original : ObjectMetadata,
  method : String,
  body : String,
) -> Result[ObjectMutationRequest, ObjectRequestIssue] {
  let path = match mutation_path(binding, original) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let preimage : Json = {
    "version": "actql-gcs-object-mutation-request/0.1",
    "resource_origin": "https://storage.googleapis.com",
    "method": method.to_json(),
    "path": path.to_json(),
    "body": body.to_json(),
    "catalog_cid": binding.catalog_cid.to_json(),
    "installation_cid": binding.installation_cid.to_json(),
    "contract_cid": binding.contract_cid.to_json(),
    "permissions": Json::array(
      binding.permissions.map(value => value.to_json()),
    ),
  }
  let wire = match
    mutation_json(
      preimage,
      binding.limits.max_identity_bytes,
      binding.limits.metadata,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    binding,
    original,
    method,
    path,
    body,
    cid: "sha256:" + @sha.hex(@utf8.encode(wire)),
  })
}

///|
// PATCH's nested metadata merge is not an ActQL whole-map replacement. Emit
// explicit nulls for old keys omitted by a supplied new map, preserving exact
// opaque keys/values. The Connector-owned marker cannot be user-overwritten.
pub fn prepare_object_metadata_patch(
  binding : ObjectMutationBinding,
  original : ObjectMetadata,
  changes : Bytes,
  marker : String,
) -> Result[ObjectMutationRequest, ObjectRequestIssue] {
  if binding.kind != PatchMetadata || !mutation_cid(marker) {
    return Err(InvalidBinding)
  }
  let limits = binding.limits.metadata
  let parsed = match
    @source.parse_json_bytes_preserving(changes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidChanges)
  }
  let root = match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidChanges)
  }
  guard @decode.closed_object(root, ["content_type", "metadata"]) is Ok(object) else {
    return Err(InvalidChanges)
  }
  let body : Map[String, Json] = Map([])
  if @decode.lookup(object, "content_type") is Some(content_type) {
    guard @decode.text(content_type) is Ok(value) else {
      return Err(InvalidChanges)
    }
    body["contentType"] = value.to_json()
  }
  let patch : Map[String, Json] = Map([])
  if @decode.lookup(object, "metadata") is Some(metadata) {
    guard @decode.object_length(metadata) is Some(count) else {
      return Err(InvalidChanges)
    }
    if count > limits.max_metadata_entries {
      return Err(CapacityExceeded)
    }
    let desired : Map[String, Json] = Map([])
    for index in 0..<count {
      guard @decode.field_at(metadata, index) is Some((key, value)) &&
        @decode.text(value) is Ok(text) else {
        return Err(InvalidChanges)
      }
      if key == "actql-request" {
        return Err(ReservedMetadata)
      }
      desired[key] = text.to_json()
    }
    if original.fields.metadata is Some(entries) {
      for (key, _) in entries {
        if key != "actql-request" && !desired.contains(key) {
          patch[key] = Null
        }
      }
    }
    for key, value in desired {
      patch[key] = value
    }
  }
  patch["actql-request"] = marker.to_json()
  body["metadata"] = Json::object(patch)
  let body = match
    mutation_json(
      Json::object(body),
      binding.limits.max_body_bytes,
      binding.limits.metadata,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  mutation_request(binding, original, "PATCH", body)
}

///|
pub fn prepare_object_delete(
  binding : ObjectMutationBinding,
  original : ObjectMetadata,
) -> Result[ObjectMutationRequest, ObjectRequestIssue] {
  if binding.kind != DeleteObject {
    return Err(InvalidBinding)
  }
  mutation_request(binding, original, "DELETE", "")
}

///|
// The apply owner checks current authorization separately. An equal physical
// payload under a copied/foreign binding cannot replace this original handle.
pub fn recheck_object_mutation(
  binding : ObjectMutationBinding,
  request : ObjectMutationRequest,
  current : ObjectMetadata,
) -> Result[Unit, ObjectRequestIssue] {
  if !physical_equal(binding, request.binding) {
    return Err(ForeignBinding)
  }
  let before = request.original.fields
  let after = current.fields
  if before.bucket != after.bucket ||
    before.name != after.name ||
    before.generation != after.generation ||
    before.metageneration != after.metageneration {
    return Err(StaleObservation)
  }
  Ok(())
}

///|
pub fn object_mutation_method(request : ObjectMutationRequest) -> String {
  request.method
}

///|
pub fn object_mutation_path(request : ObjectMutationRequest) -> String {
  request.path
}

///|
pub fn object_mutation_body(request : ObjectMutationRequest) -> String {
  request.body
}

///|
pub fn object_mutation_cid(request : ObjectMutationRequest) -> String {
  request.cid
}
