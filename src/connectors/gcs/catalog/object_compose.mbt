// Exact composition material in the existing GCS Owner. Reference admission,
// read approval, funded acquisition, dispatch and recovery remain separate.

///|
pub struct ObjectComposeBinding {
  target : ObjectUploadBinding
  max_sources : Int
  max_result_bytes : Int64
}

///|
// The caller must select the complete intended properties explicitly. This
// primitive neither chooses metadata inheritance nor invents authored defaults.
pub(all) struct ObjectComposeProperties {
  content_type : String?
  content_encoding : String?
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
  if max_sources < 1 || max_sources > 32 || max_result_bytes < 0L {
    return Err(InvalidBinding)
  }
  Ok({ target, max_sources, max_result_bytes })
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
      matrix = Array::makei(32, index => compose_matrix_apply(original, original[index]))
    }
  }
  value ^ second
}

///|
fn compose_properties(
  properties : ObjectComposeProperties,
  marker : String,
  limits : ObjectMetadataLimits,
) -> Result[(ObjectComposeProperties, Json), ObjectUploadIssue] {
  // The private marker is one real physical metadata entry, not free space.
  if properties.metadata.length() >= limits.max_metadata_entries {
    return Err(CapacityExceeded)
  }
  let metadata : Map[String, Json] = Map([])
  for (key, value) in properties.metadata {
    if key == "actql-request" || metadata.contains(key) {
      return Err(InvalidInput)
    }
    metadata[key] = value.to_json()
  }
  metadata["actql-request"] = marker.to_json()
  let destination : Map[String, Json] = Map([])
  destination["metadata"] = Json::object(metadata)
  if properties.content_type is Some(value) {
    if @contract.admit_content_media_type_descriptor(value, limits.max_bytes) is Err(_) {
      return Err(InvalidInput)
    }
    destination["contentType"] = value.to_json()
  }
  if properties.content_encoding is Some(value) {
    if !upload_text(value, limits.max_bytes) {
      return Err(InvalidInput)
    }
    destination["contentEncoding"] = value.to_json()
  }
  Ok((
    { ..properties, metadata: properties.metadata.copy(), },
    Json::object(destination),
  ))
}

///|
pub fn prepare_object_compose(
  binding : ObjectComposeBinding,
  before : ObjectUploadObservation,
  sources : Array[ObjectMetadata],
  properties : ObjectComposeProperties,
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
    compose_properties(properties, marker, target.limits.metadata) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let mut size = 0L
  let mut checksum : UInt = 0
  let mut storage_class : String? = None
  let source_objects = []
  // Preserve original order and repetitions. Sorting/deduplication changes
  // the bytes, and a source can also be the original destination generation.
  for source in sources {
    let fields = source.fields
    if fields.bucket != target.bucket || !upload_name(target, fields.name) {
      return Err(InvalidInput)
    }
    guard fields.storage_class is Some(observed_class) &&
      fields.crc32c is Some(crc) && compose_crc_value(crc) is Some(crc) else {
      return Err(InvalidInput)
    }
    if !upload_text(observed_class, 128) {
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
  guard destination is Object(destination) else { abort("internal compose destination") }
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
    before.original.map(value => value.fields.generation.to_string()).unwrap_or("0") +
    before.original.map(value => {
      "&ifMetagenerationMatch=" + value.fields.metageneration.to_string()
    }).unwrap_or("")
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
    "source_responses_sha256": Json::array(sources.map(value => value.response_sha256.to_json())),
  }
  let wire = match upload_json(preimage, target.limits.max_identity_bytes, target.limits.metadata) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ binding, before, sources: sources.copy(), properties, storage_class,
    path, body, marker, size, crc32c: compose_crc_text(checksum),
    cid: "sha256:" + @sha.hex(@utf8.encode(wire)) })
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
  if current.name != request.before.name || sources.length() != request.sources.length() {
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
    if before.bucket != now.bucket || before.name != now.name ||
      before.generation != now.generation || before.metageneration != now.metageneration ||
      before.size != now.size || before.crc32c != now.crc32c ||
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
  if !physical_equal(binding, request.binding) { Err(ForeignBinding) } else { Ok(request.body) }
}

///|
pub fn object_compose_cid(request : ObjectComposeRequest) -> String { request.cid }

///|
// Correlation/consistency only. The existing original dispatch and retained
// approved request must separately authenticate a direct or recovery response.
pub fn object_compose_response_matches(
  binding : ObjectComposeBinding,
  request : ObjectComposeRequest,
  response : ObjectMetadata,
) -> Bool {
  if !physical_equal(binding, request.binding) { return false }
  let fields = response.fields
  let original = request.before.original
  let newer = original.map(value => fields.generation > value.fields.generation).unwrap_or(true)
  let expected_metadata = request.properties.metadata.copy()
  expected_metadata.sort_by((left, right) => left.0.lexical_compare(right.0))
  let actual_metadata = logical_metadata(fields.metadata).unwrap_or([])
  actual_metadata.sort_by((left, right) => left.0.lexical_compare(right.0))
  fields.bucket == binding.target.bucket && fields.name == request.before.name &&
  newer && fields.metageneration == 1L && fields.size == request.size &&
  fields.crc32c == Some(request.crc32c) && fields.storage_class == Some(request.storage_class) &&
  (request.properties.content_type is None || fields.content_type == request.properties.content_type) &&
  fields.content_encoding == request.properties.content_encoding &&
  expected_metadata == actual_metadata &&
  fields.metadata.unwrap_or([]).any(entry => entry == ("actql-request", request.marker))
}
