// Original provider requests only. Content custody, approval, the durable
// dispatch claim and uncertain outcomes remain with the existing owners.

///|
pub(all) enum ObjectUploadIssue {
  InvalidBinding
  InvalidInput
  ForeignBinding
  ContentMismatch
  TargetExists
  StaleObservation
  CapacityExceeded
  RequiresResumable
} derive(Eq, Debug)

///|
pub(all) struct ObjectUploadLimits {
  metadata : ObjectMetadataLimits
  max_content_bytes : Int
  max_body_bytes : Int
  max_path_bytes : Int
  max_identity_bytes : Int
}

///|
pub struct ObjectUploadBinding {
  collection : ObjectCollectionBinding
  bucket : String
  prefix : String
  catalog_cid : String
  command_cid : String
  permissions : Array[String]
  limits : ObjectUploadLimits
}

///|
// An explicit observed 404 is not an omitted/unobserved target. The original
// physical observation is retained even when there was no object to parse.
pub struct ObjectUploadObservation {
  binding : ObjectUploadBinding
  name : String
  original : ObjectMetadata?
  response_sha256 : String
}

///|
pub struct ObjectUploadRequest {
  binding : ObjectUploadBinding
  before : ObjectUploadObservation
  path : String
  body : Bytes
  body_media_type : String
  content_type : String
  content_size : Int
  content_crc32c : String
  marker : String
  cid : String
}

///|
fn upload_text(value : String, maximum : Int, empty? : Bool = false) -> Bool {
  (empty || !value.is_empty()) &&
  @scalar.admit_utf8_length(value, maximum) is Ok(_) &&
  value
  .iter()
  .all(character => character.to_int() >= 32 && character.to_int() != 127)
}

///|
// Provider object text is opaque Unicode. XML/CLI compatibility advice is
// not an additional naming restriction for the JSON upload API.
fn upload_object_text(value : String, empty? : Bool = false) -> Bool {
  (empty || !value.is_empty()) &&
  @scalar.admit_utf8_length(value, 1024) is Ok(_) &&
  !value.contains("\r") &&
  !value.contains("\n")
}

///|
fn upload_name(binding : ObjectUploadBinding, name : String) -> Bool {
  upload_object_text(name) &&
  name != "." &&
  name != ".." &&
  !name.has_prefix(".well-known/acme-challenge/") &&
  name.has_prefix(binding.prefix)
}

///|
// This is an original binding's current-object GET, not a versioned Content
// request or an authorization decision. The exact path is checked before I/O.
pub fn object_upload_metadata_path(
  binding : ObjectUploadBinding,
  name : String,
) -> Result[String, ObjectUploadIssue] {
  if !upload_name(binding, name) {
    return Err(InvalidInput)
  }
  let maximum = binding.limits.max_path_bytes
  let bucket = match mutation_part(binding.bucket, maximum) {
    Ok(value) => value
    Err(_) => return Err(CapacityExceeded)
  }
  let object_name = match mutation_part(name, maximum) {
    Ok(value) => value
    Err(_) => return Err(CapacityExceeded)
  }
  let path = "/storage/v1/b/" + bucket + "/o/" + object_name
  if @scalar.admit_utf8_length(path, maximum) is Err(_) {
    Err(CapacityExceeded)
  } else {
    Ok(path)
  }
}

///|
pub fn object_upload_metadata_max_bytes(binding : ObjectUploadBinding) -> Int {
  binding.limits.metadata.max_bytes
}

///|
// Borrow the actual collection; do not recreate one from its equal DATA wire.
// These declarations do not themselves establish an installed permission.
pub fn prepare_object_upload_binding(
  collection : ObjectCollectionBinding,
  command_cid : String,
  permissions : Array[String],
  limits : ObjectUploadLimits,
) -> Result[ObjectUploadBinding, ObjectUploadIssue] {
  if !mutation_cid(command_cid) ||
    limits.max_content_bytes < 0 ||
    limits.max_body_bytes < 1 ||
    limits.max_path_bytes < 1 ||
    limits.max_identity_bytes < 1 ||
    permissions.is_empty() ||
    permissions.length() > 64 {
    return Err(InvalidBinding)
  }
  let identity = match
    metadata_cursor(@utf8.encode(collection.identity_wire), limits.metadata) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  let resource = match
    metadata_cursor(@utf8.encode(collection.resource_wire), limits.metadata) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  guard @decode.open_object(identity) is Ok(identity) &&
    metadata_text(identity, "resource_kind", 128) is Some("file_collection") &&
    @decode.required(identity, "collection_identity") is Ok(scope) &&
    @decode.open_object(scope) is Ok(scope) &&
    metadata_text(scope, "bucket", 222) is Some(bucket) &&
    metadata_text(scope, "prefix", 1024, empty=true) is Some(prefix) &&
    @decode.open_object(resource) is Ok(resource) &&
    metadata_text(resource, "boundary_cid", 71) is Some(catalog_cid) else {
    return Err(InvalidBinding)
  }
  if !upload_text(bucket, 222) || !upload_object_text(prefix, empty=true) {
    return Err(InvalidBinding)
  }
  let owned = permissions.copy()
  // Core String Compare is length-first; request-set identities use exact
  // lexical text order, independently of the permission's length.
  owned.sort_by((left, right) => left.lexical_compare(right))
  for index in 0..<owned.length() {
    if !upload_text(owned[index], 256) ||
      (index > 0 && owned[index] == owned[index - 1]) {
      return Err(InvalidBinding)
    }
  }
  Ok({
    collection,
    bucket,
    prefix,
    catalog_cid,
    command_cid,
    permissions: owned,
    limits,
  })
}

///|
pub fn admit_object_upload_observation(
  binding : ObjectUploadBinding,
  name : String,
  status : Int,
  bytes : Bytes,
) -> Result[ObjectUploadObservation, ObjectUploadIssue] {
  if !upload_name(binding, name) {
    return Err(InvalidInput)
  }
  if bytes.length() > binding.limits.metadata.max_bytes {
    return Err(CapacityExceeded)
  }
  let original = match status {
    404 => None
    200 => {
      let value = match
        admit_object_metadata(
          bytes,
          binding.bucket,
          binding.prefix,
          Some(name),
          binding.limits.metadata,
        ) {
        Ok(value) => value
        Err(BudgetExceeded) => return Err(CapacityExceeded)
        Err(_) => return Err(InvalidInput)
      }
      Some(value)
    }
    _ => return Err(InvalidInput)
  }
  Ok({ binding, name, original, response_sha256: @sha.hex(bytes), })
}

///|
fn upload_crc32c(bytes : Bytes) -> String {
  let mut crc : UInt = 0xffffffff
  for byte in bytes {
    crc = crc ^ byte.to_uint()
    for _ in 0..<8 {
      crc = (crc >> 1) ^ (if (crc & 1) == 1 { 0x82f63b78 } else { 0 })
    }
  }
  crc = crc ^ 0xffffffff
  @base64.encode(
    Bytes::makei(4, index => (crc >> (24 - 8 * index)).to_byte()).view(),
  )
}

///|
fn upload_json(
  value : Json,
  maximum : Int,
  limits : ObjectMetadataLimits,
) -> Result[String, ObjectUploadIssue] {
  mutation_json(value, maximum, limits).map_err(_ => CapacityExceeded)
}

///|
// The explicit multipart entry does not downgrade a large upload to this
// route: its caller must use the retained resumable-session path above 8 MiB.
// Body framing is byte-exact and remains provider-owned on every backend.
pub fn prepare_object_multipart_upload(
  binding : ObjectUploadBinding,
  before : ObjectUploadObservation,
  content : Bytes,
  content_ref_cid : String,
  expected_content_cid : String,
  content_type : String,
  overwrite : Bool?,
  marker : String,
) -> Result[ObjectUploadRequest, ObjectUploadIssue] {
  if !physical_equal(binding, before.binding) {
    return Err(ForeignBinding)
  }
  if !mutation_cid(content_ref_cid) ||
    !mutation_cid(expected_content_cid) ||
    !mutation_cid(marker) ||
    @contract.admit_content_media_type_descriptor(
      content_type,
      binding.limits.metadata.max_bytes,
    )
    is Err(_) {
    return Err(InvalidInput)
  }
  if content.length() > binding.limits.max_content_bytes {
    return Err(CapacityExceeded)
  }
  if content.length() > 8 * 1024 * 1024 {
    return Err(RequiresResumable)
  }
  let content_hash = @sha.hex(content)
  if "sha256:" + content_hash != expected_content_cid {
    return Err(ContentMismatch)
  }
  if !overwrite.unwrap_or(false) && before.original is Some(_) {
    return Err(TargetExists)
  }
  let bucket = match
    mutation_part(binding.bucket, binding.limits.max_path_bytes) {
    Ok(value) => value
    Err(_) => return Err(CapacityExceeded)
  }
  let generation = before.original
    .map(value => value.fields.generation.to_string())
    .unwrap_or("0")
  let path = "/upload/storage/v1/b/" +
    bucket +
    "/o?uploadType=multipart&ifGenerationMatch=" +
    generation +
    before.original
    .map(value => {
      "&ifMetagenerationMatch=" + value.fields.metageneration.to_string()
    })
    .unwrap_or("")
  if @scalar.admit_utf8_length(path, binding.limits.max_path_bytes) is Err(_) {
    return Err(CapacityExceeded)
  }
  let crc32c = upload_crc32c(content)
  let metadata = match
    upload_json(
      {
        "name": before.name.to_json(),
        "contentType": content_type.to_json(),
        "crc32c": crc32c.to_json(),
        "metadata": { "actql-request": marker.to_json() },
      },
      binding.limits.metadata.max_bytes,
      binding.limits.metadata,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let boundary = "actql-" + content_hash
  let separator = @utf8.encode("\r\n--" + boundary)
  if content.find(separator.view()) is Some(_) {
    return Err(InvalidInput)
  }
  let head = @utf8.encode(
    "--" +
    boundary +
    "\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n" +
    metadata +
    "\r\n--" +
    boundary +
    "\r\nContent-Type: " +
    content_type +
    "\r\n\r\n",
  )
  let tail = @utf8.encode("\r\n--" + boundary + "--\r\n")
  let maximum = binding.limits.max_body_bytes
  // Checked subtraction precedes the body allocation; no Int wrap or
  // rejected over-size concatenation is hidden behind a later clamp.
  if head.length() > maximum ||
    content.length() > maximum - head.length() ||
    tail.length() > maximum - head.length() - content.length() {
    return Err(CapacityExceeded)
  }
  let length = head.length() + content.length() + tail.length()
  let bytes : FixedArray[Byte] = FixedArray::make(length, 0)
  bytes.blit_from_bytes(0, head, 0, head.length())
  bytes.blit_from_bytes(head.length(), content, 0, content.length())
  bytes.blit_from_bytes(
    head.length() + content.length(),
    tail,
    0,
    tail.length(),
  )
  let body = Bytes::from_array(bytes[:])
  let body_media_type = "multipart/related; boundary=" + boundary
  let wire = match
    upload_request_wire(
      binding, before, path, body, body_media_type, content_ref_cid, expected_content_cid,
      overwrite,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    binding,
    before,
    path,
    body,
    body_media_type,
    content_type,
    content_size: content.length(),
    content_crc32c: crc32c,
    marker,
    cid: "sha256:" + @sha.hex(@utf8.encode(wire)),
  })
}

///|
fn upload_request_wire(
  binding : ObjectUploadBinding,
  before : ObjectUploadObservation,
  path : String,
  body : Bytes,
  body_media_type : String,
  content_ref_cid : String,
  expected_content_cid : String,
  overwrite : Bool?,
) -> Result[String, ObjectUploadIssue] {
  let preimage : Json = {
    "version": "actql-gcs-object-upload-request/0.1",
    "resource_origin": "https://storage.googleapis.com",
    "method": "POST",
    "path": path.to_json(),
    "body_sha256": ("sha256:" + @sha.hex(body)).to_json(),
    "body_bytes": body.length().to_json(),
    "body_media_type": body_media_type.to_json(),
    "collection_identity_cid": binding.collection.identity_cid.to_json(),
    "catalog_cid": binding.catalog_cid.to_json(),
    "installation_cid": binding.collection.installation_cid.to_json(),
    "command_cid": binding.command_cid.to_json(),
    "permissions": Json::array(
      binding.permissions.map(value => value.to_json()),
    ),
    "original_response_sha256": before.response_sha256.to_json(),
    "content_ref_cid": content_ref_cid.to_json(),
    "content_cid": expected_content_cid.to_json(),
    "overwrite": match overwrite {
      Some(value) => value.to_json()
      None => Json::null()
    },
  }
  upload_json(
    preimage,
    binding.limits.max_identity_bytes,
    binding.limits.metadata,
  )
}

///|
pub fn recheck_object_upload(
  binding : ObjectUploadBinding,
  request : ObjectUploadRequest,
  current : ObjectUploadObservation,
) -> Result[Unit, ObjectUploadIssue] {
  if !physical_equal(binding, request.binding) ||
    !physical_equal(binding, current.binding) {
    return Err(ForeignBinding)
  }
  if current.name != request.before.name {
    return Err(StaleObservation)
  }
  match (request.before.original, current.original) {
    (None, None) => Ok(())
    (Some(original), Some(current)) =>
      if original.fields.generation == current.fields.generation &&
        original.fields.metageneration == current.fields.metageneration {
        Ok(())
      } else {
        Err(StaleObservation)
      }
    _ => Err(StaleObservation)
  }
}

///|
pub fn object_upload_body_for(
  binding : ObjectUploadBinding,
  request : ObjectUploadRequest,
) -> Result[Bytes, ObjectUploadIssue] {
  if !physical_equal(binding, request.binding) {
    Err(ForeignBinding)
  } else {
    // Foreign runtimes can mutate Bytes: never export the sealed backing.
    Ok(Bytes::makei(request.body.length(), index => request.body[index]))
  }
}

///|
pub fn object_upload_cid(request : ObjectUploadRequest) -> String {
  request.cid
}

///|
pub fn object_upload_path(request : ObjectUploadRequest) -> String {
  request.path
}

///|
pub fn object_upload_body_media_type(request : ObjectUploadRequest) -> String {
  request.body_media_type
}

///|
// Targeted Preview DATA omits the marker value, but explicitly declares that
// this same approved operation assigns the private Connector protocol key.
pub fn object_upload_projection_json(
  binding : ObjectUploadBinding,
  request : ObjectUploadRequest,
  max_bytes : Int,
) -> Result[String, ObjectUploadIssue] {
  if !physical_equal(binding, request.binding) {
    return Err(ForeignBinding)
  }
  if max_bytes < 1 {
    return Err(CapacityExceeded)
  }
  upload_json(
    {
      "origin": "https://storage.googleapis.com",
      "operation": "gcs:object:upload",
      "method": "POST",
      "path": request.path.to_json(),
      "request_cid": request.cid.to_json(),
      "bucket": binding.bucket.to_json(),
      "name": request.before.name.to_json(),
      "content_type": request.content_type.to_json(),
      "size_bytes": request.content_size.to_json(),
      "crc32c": request.content_crc32c.to_json(),
      "body_byte_length": request.body.length().to_json(),
      "body_media_type": request.body_media_type.to_json(),
      "generation": request.before.original
      .map(value => value.fields.generation.to_string())
      .unwrap_or("0")
      .to_json(),
      "metageneration": match request.before.original {
        Some(value) => value.fields.metageneration.to_string().to_json()
        None => Json::null()
      },
      "protocol_behavior": "assign_original_request_marker:actql-request",
    },
    max_bytes,
    binding.limits.metadata,
  )
}

///|
// This is response DATA consistency only. A retained original claim/approved
// Preview/current issuer must authenticate its use; it never settles an Effect.
pub fn object_upload_response_matches(
  binding : ObjectUploadBinding,
  request : ObjectUploadRequest,
  response : ObjectMetadata,
) -> Bool {
  if !physical_equal(binding, request.binding) {
    return false
  }
  let fields = response.fields
  // A replacement has a distinct generation; numeric ordering is not promised.
  let distinct_generation = request.before.original
    .map(original => fields.generation != original.fields.generation)
    .unwrap_or(true)
  fields.bucket == binding.bucket &&
  fields.name == request.before.name &&
  distinct_generation &&
  fields.metageneration == 1L &&
  fields.size == request.content_size.to_int64() &&
  fields.content_type == Some(request.content_type) &&
  fields.crc32c == Some(request.content_crc32c) &&
  fields.metadata
  .unwrap_or([])
  .any(entry => entry == ("actql-request", request.marker))
}
