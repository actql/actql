// Exact composition material in the existing GCS Owner. Reference admission,
// read approval, funded acquisition, dispatch and recovery remain separate.

///|
pub struct ObjectComposeBinding {
  target : ObjectUploadBinding
  max_sources : Int
  max_result_bytes : Int64
}

///|
// Selected from original Preview observations, never mutable current config.
struct ObjectComposeProperties {
  content_type : String
  metadata : Array[(String, String)]
}

///|
pub struct ObjectComposeRequest {
  binding : ObjectComposeBinding
  before : ObjectUploadObservation
  sources : Array[ObjectMetadata]
  properties : ObjectComposeProperties
  storage_class : String
  path : String
  body : String
  marker : String
  size : Int64
  crc32c : String
  cid : String
}

///|
// ObjectUploadBinding is the existing original collection/Command/permission
// DATA binding. Its name does not issue an upload or compose permission.
pub fn prepare_object_compose_binding(
  target : ObjectUploadBinding,
  max_sources : Int,
  max_result_bytes : Int64,
) -> Result[ObjectComposeBinding, ObjectUploadIssue] {
  if max_sources < 1 ||
    max_sources > 32 ||
    max_result_bytes < 0L ||
    max_result_bytes > 5497558138880L {
    return Err(InvalidBinding)
  }
  Ok({ target, max_sources, max_result_bytes, })
}

///|
fn compose_crc_value(text : String) -> UInt? {
  if !content_digest(text, 4) {
    return None
  }
  let bytes = @base64.decode(text[:]) catch { _ => return None }
  let mut value : UInt = 0
  for byte in bytes {
    value = (value << 8) | byte.to_uint()
  }
  Some(value)
}

///|
fn compose_crc_text(value : UInt) -> String {
  @base64.encode(
    Bytes::makei(4, index => (value >> (24 - index * 8)).to_byte()).view(),
  )
}

///|
fn compose_matrix_apply(matrix : Array[UInt], vector : UInt) -> UInt {
  let mut result : UInt = 0
  let mut bits = vector
  let mut index = 0
  while bits != 0 {
    if (bits & 1) != 0 {
      result = result ^ matrix[index]
    }
    bits = bits >> 1
    index += 1
  }
  result
}

///|
// Shift the finalized Castagnoli remainder by exactly `length` bytes, then
// xor the second finalized remainder. No source payload is read/concatenated.
// Two 32-element matrices suffice; at most 63 squarings per Int64 length.
fn compose_crc_join(first : UInt, second : UInt, length : Int64) -> UInt {
  let mut matrix = Array::makei(32, index => {
    let mut basis : UInt = 1 << index
    for _ in 0..<8 {
      basis = (basis >> 1) ^ (if (basis & 1) == 1 { 0x82f63b78 } else { 0 })
    }
    basis
  })
  let mut remaining = length
  let mut value = first
  while remaining > 0L {
    if (remaining & 1L) == 1L {
      value = compose_matrix_apply(matrix, value)
    }
    remaining = remaining >> 1
    if remaining > 0L {
      let original = matrix
      matrix = Array::makei(32, index => {
        compose_matrix_apply(original, original[index])
      })
    }
  }
  value ^ second
}

///|
fn compose_properties(
  before : ObjectUploadObservation,
  first : ObjectMetadata,
  marker : String,
  limits : ObjectMetadataLimits,
) -> Result[(ObjectComposeProperties, Json), ObjectUploadIssue] {
  let original = before.original.unwrap_or(first)
  guard original.fields.content_type is Some(content_type) &&
    @contract.admit_content_media_type_descriptor(
      content_type,
      limits.max_bytes,
    )
    is Ok(_) else {
    return Err(InvalidInput)
  }
  // This finite profile does not promise preservation of a separate encoded
  // representation, ACL, encryption or retention settings.
  if original.fields.content_encoding is Some(value) && value != "identity" {
    return Err(InvalidInput)
  }
  let entries = before.original
    .map(value => logical_metadata(value.fields.metadata).unwrap_or([]))
    .unwrap_or([])
  // The private marker is one real physical metadata entry, not free space.
  if entries.length() >= limits.max_metadata_entries {
    return Err(CapacityExceeded)
  }
  let metadata : Map[String, Json] = Map([])
  for (key, value) in entries {
    metadata[key] = value.to_json()
  }
  metadata["actql-request"] = marker.to_json()
  let destination : Map[String, Json] = Map([])
  destination["metadata"] = Json::object(metadata)
  destination["contentType"] = content_type.to_json()
  Ok(({ content_type, metadata: entries, }, Json::object(destination)))
}

///|
pub fn prepare_object_compose(
  binding : ObjectComposeBinding,
  before : ObjectUploadObservation,
  sources : Array[ObjectMetadata],
  marker : String,
) -> Result[ObjectComposeRequest, ObjectUploadIssue] {
  let target = binding.target
  if !physical_equal(target, before.binding) {
    return Err(ForeignBinding)
  }
  if !mutation_cid(marker) || sources.is_empty() {
    return Err(InvalidInput)
  }
  if sources.length() > binding.max_sources {
    return Err(CapacityExceeded)
  }
  let (properties, destination) = match
    compose_properties(before, sources[0], marker, target.limits.metadata) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let mut size = 0L
  let mut checksum : UInt = 0
  let mut storage_class : String? = None
  let source_objects : Array[Json] = []
  // Preserve original order and repetitions. Sorting/deduplication changes
  // the bytes, and a source can also be the original destination generation.
  for source in sources {
    let fields = source.fields
    if fields.bucket != target.bucket || !upload_name(target, fields.name) {
      return Err(InvalidInput)
    }
    guard fields.storage_class is Some(observed_class) &&
      fields.crc32c is Some(crc) &&
      compose_crc_value(crc) is Some(crc) else {
      return Err(InvalidInput)
    }
    if !upload_text(observed_class, 128) {
      return Err(InvalidInput)
    }
    if fields.content_encoding is Some(value) && value != "identity" {
      return Err(InvalidInput)
    }
    if storage_class is Some(previous) && previous != observed_class {
      return Err(InvalidInput)
    }
    storage_class = Some(observed_class)
    if fields.size > binding.max_result_bytes - size {
      return Err(CapacityExceeded)
    }
    if fields.size == 0L && crc != 0 {
      return Err(InvalidInput)
    }
    size += fields.size
    checksum = compose_crc_join(checksum, crc, fields.size)
    source_objects.push({
      "name": fields.name.to_json(),
      "generation": fields.generation.to_string().to_json(),
      "objectPreconditions": {
        "ifGenerationMatch": fields.generation.to_string().to_json(),
      },
    })
  }
  let storage_class = storage_class.unwrap()
  guard destination is Object(destination) else {
    abort("internal compose destination")
  }
  destination["name"] = before.name.to_json()
  destination["storageClass"] = storage_class.to_json()
  let body = match
    upload_json(
      {
        "sourceObjects": Json::array(source_objects),
        "destination": Json::object(destination),
        "deleteSourceObjects": false,
      },
      target.limits.max_body_bytes,
      target.limits.metadata,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let metadata_path = match object_upload_metadata_path(target, before.name) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let path = metadata_path +
    "/compose?ifGenerationMatch=" +
    before.original
    .map(value => value.fields.generation.to_string())
    .unwrap_or("0") +
    before.original
    .map(value => {
      "&ifMetagenerationMatch=" + value.fields.metageneration.to_string()
    })
    .unwrap_or("")
  if @scalar.admit_utf8_length(path, target.limits.max_path_bytes) is Err(_) {
    return Err(CapacityExceeded)
  }
  let preimage : Json = {
    "version": "actql-gcs-object-compose-request/0.1",
    "resource_origin": "https://storage.googleapis.com",
    "method": "POST",
    "path": path.to_json(),
    "body": body.to_json(),
    "collection_identity_cid": target.collection.identity_cid.to_json(),
    "catalog_cid": target.catalog_cid.to_json(),
    "installation_cid": target.collection.installation_cid.to_json(),
    "command_cid": target.command_cid.to_json(),
    "permissions": Json::array(target.permissions.map(value => value.to_json())),
    "original_response_sha256": before.response_sha256.to_json(),
    "source_responses_sha256": Json::array(
      sources.map(value => value.response_sha256.to_json()),
    ),
  }
  let wire = match
    upload_json(
      preimage,
      target.limits.max_identity_bytes,
      target.limits.metadata,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    binding,
    before,
    sources: sources.copy(),
    properties,
    storage_class,
    path,
    body,
    marker,
    size,
    crc32c: compose_crc_text(checksum),
    cid: "sha256:" + @sha.hex(@utf8.encode(wire)),
  })
}

///|
pub fn recheck_object_compose(
  binding : ObjectComposeBinding,
  request : ObjectComposeRequest,
  current : ObjectUploadObservation,
  sources : Array[ObjectMetadata],
) -> Result[Unit, ObjectUploadIssue] {
  if !physical_equal(binding, request.binding) ||
    !physical_equal(binding.target, current.binding) {
    return Err(ForeignBinding)
  }
  if current.name != request.before.name ||
    sources.length() != request.sources.length() {
    return Err(StaleObservation)
  }
  match (request.before.original, current.original) {
    (None, None) => ()
    (Some(before), Some(now)) =>
      if before.fields.generation != now.fields.generation ||
        before.fields.metageneration != now.fields.metageneration {
        return Err(StaleObservation)
      }
    _ => return Err(StaleObservation)
  }
  for index in 0..<sources.length() {
    let before = request.sources[index].fields
    let now = sources[index].fields
    if before.bucket != now.bucket ||
      before.name != now.name ||
      before.generation != now.generation ||
      before.metageneration != now.metageneration ||
      before.size != now.size ||
      before.crc32c != now.crc32c ||
      before.storage_class != now.storage_class {
      return Err(StaleObservation)
    }
  }
  Ok(())
}

///|
pub fn object_compose_body_for(
  binding : ObjectComposeBinding,
  request : ObjectComposeRequest,
) -> Result[String, ObjectUploadIssue] {
  if !physical_equal(binding, request.binding) {
    Err(ForeignBinding)
  } else {
    Ok(request.body)
  }
}

///|
pub fn object_compose_cid(request : ObjectComposeRequest) -> String {
  request.cid
}

///|
// Targeted Preview/control DATA. Original response hashes and the private
// marker stay in the sealed physical request, not the human metadata map.
pub fn object_compose_projection_json(
  binding : ObjectComposeBinding,
  request : ObjectComposeRequest,
  max_bytes : Int,
) -> Result[String, ObjectUploadIssue] {
  if !physical_equal(binding, request.binding) {
    return Err(ForeignBinding)
  }
  if max_bytes < 1 {
    return Err(CapacityExceeded)
  }
  let metadata : Map[String, Json] = Map([])
  for (key, value) in request.properties.metadata {
    metadata[key] = value.to_json()
  }
  let body_bytes = match
    @scalar.admit_utf8_length(
      request.body,
      binding.target.limits.max_body_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(CapacityExceeded)
  }
  let sources : Array[Json] = request.sources.map(value => {
    let fields = value.fields
    {
      "name": fields.name.to_json(),
      "generation": fields.generation.to_string().to_json(),
      "metageneration": fields.metageneration.to_string().to_json(),
      "size_bytes": fields.size.to_string().to_json(),
      "crc32c": fields.crc32c.unwrap().to_json(),
    }
  })
  upload_json(
    {
      "origin": "https://storage.googleapis.com",
      "operation": "gcs:object:compose",
      "method": "POST",
      "path": request.path.to_json(),
      "request_cid": request.cid.to_json(),
      "body_media_type": "application/json",
      "body_byte_length": body_bytes.to_json(),
      "bucket": binding.target.bucket.to_json(),
      "name": request.before.name.to_json(),
      "before": request.before.original
      .map(value => metadata_fields_json(object_metadata_fields(value)))
      .unwrap_or(Json::null()),
      "after": {
        "content_type": request.properties.content_type.to_json(),
        "metadata": Json::object(metadata),
        "size_bytes": request.size.to_string().to_json(),
        "storage_class": request.storage_class.to_json(),
        "crc32c": request.crc32c.to_json(),
      },
      "sources": Json::array(sources),
      "protocol_behavior": "assign_original_request_marker:actql-request",
      "property_selection": (if request.before.original is Some(_) {
        "captured_destination"
      } else {
        "first_source_type_empty_user_metadata"
      }).to_json(),
    },
    max_bytes,
    binding.target.limits.metadata,
  )
}

///|
// Correlation/consistency only. The existing original dispatch and retained
// approved request must separately authenticate a direct or recovery response.
pub fn object_compose_response_matches(
  binding : ObjectComposeBinding,
  request : ObjectComposeRequest,
  response : ObjectMetadata,
) -> Bool {
  if !physical_equal(binding, request.binding) {
    return false
  }
  let fields = response.fields
  let original = request.before.original
  // Cloud Storage generations distinguish versions; their numeric order is
  // not guaranteed. The same generation can never prove a replacement.
  let distinct_generation = original
    .map(value => fields.generation != value.fields.generation)
    .unwrap_or(true)
  let expected_metadata = request.properties.metadata.copy()
  expected_metadata.sort_by((left, right) => left.0.lexical_compare(right.0))
  let actual_metadata = logical_metadata(fields.metadata).unwrap_or([])
  actual_metadata.sort_by((left, right) => left.0.lexical_compare(right.0))
  fields.bucket == binding.target.bucket &&
  fields.name == request.before.name &&
  distinct_generation &&
  fields.metageneration == 1L &&
  fields.size == request.size &&
  fields.crc32c == Some(request.crc32c) &&
  fields.storage_class == Some(request.storage_class) &&
  fields.content_type == Some(request.properties.content_type) &&
  (
    fields.content_encoding is None ||
    fields.content_encoding == Some("identity")
  ) &&
  expected_metadata == actual_metadata &&
  fields.metadata
  .unwrap_or([])
  .any(entry => entry == ("actql-request", request.marker))
}

///|
// Only the existing Owner's original direct response can select a typed
// failure. A failed later GET never proves non-apply or permits a resend.
pub fn object_compose_response_projection_json(
  binding : ObjectComposeBinding,
  request : ObjectComposeRequest,
  status : Int,
  body : Bytes,
  max_bytes : Int,
) -> Result[String, ObjectUploadIssue] {
  if !physical_equal(binding, request.binding) {
    return Err(ForeignBinding)
  }
  if max_bytes < 1 || body.length() > binding.target.limits.metadata.max_bytes {
    return Err(CapacityExceeded)
  }
  let unknown : Json = { "kind": "provider-response" }
  let projection : Json = if status == 412 {
    {
      "kind": "typed-failure-response",
      "outcome": {
        "state": "failed",
        "error": {
          "code": "conflict",
          "message": "The original GCS composition precondition failed",
        },
      },
    }
  } else if status == 200 {
    match
      admit_object_metadata(
        body,
        binding.target.bucket,
        binding.target.prefix,
        Some(request.before.name),
        binding.target.limits.metadata,
      ) {
      Ok(value) =>
        if object_compose_response_matches(binding, request, value) {
          {
            "kind": "typed-success-response",
            "outcome": { "state": "applied", "result": {} },
          }
        } else {
          unknown
        }
      Err(BudgetExceeded) => return Err(CapacityExceeded)
      Err(_) => unknown
    }
  } else {
    unknown
  }
  upload_json(projection, max_bytes, binding.target.limits.metadata)
}
