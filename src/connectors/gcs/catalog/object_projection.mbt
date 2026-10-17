// Private physical projections, not public value-wire types or apply receipts.
// Decimal generation text is emitted directly from the original Int64 owner.

///|
fn metadata_fields_json(fields : ObjectMetadataFields) -> Json {
  let result : Map[String, Json] = {
    "bucket": fields.bucket.to_json(),
    "name": fields.name.to_json(),
    "generation": fields.generation.to_string().to_json(),
    "metageneration": fields.metageneration.to_string().to_json(),
    "size": fields.size.to_string().to_json(),
  }
  for
    (key, value) in [
      ("content_type", fields.content_type),
      ("content_encoding", fields.content_encoding),
      ("storage_class", fields.storage_class),
      ("updated", fields.updated),
      ("md5", fields.md5),
      ("crc32c", fields.crc32c),
    ] {
    if value is Some(value) {
      result[key] = value.to_json()
    }
  }
  if fields.metadata is Some(entries) {
    let metadata : Map[String, Json] = Map([])
    for (key, value) in entries {
      metadata[key] = value.to_json()
    }
    result["metadata"] = Json::object(metadata)
  }
  Json::object(result)
}

///|
pub fn object_metadata_logical_json(
  original : ObjectMetadata,
  limits : ObjectMetadataLimits,
) -> Result[String, ObjectMetadataIssue] {
  if limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_metadata_entries < 0 {
    return Err(InvalidLimits)
  }
  if original.fields.metadata is Some(entries) &&
    entries.length() > limits.max_metadata_entries {
    return Err(BudgetExceeded)
  }
  mutation_json(
    metadata_fields_json(object_metadata_fields(original)),
    limits.max_bytes,
    limits,
  ).map_err(_ => BudgetExceeded)
}

///|
pub fn admit_object_mutation_request(
  binding : ObjectMutationBinding,
  request : ObjectMutationRequest,
) -> Result[Unit, ObjectRequestIssue] {
  if physical_equal(binding, request.binding) {
    Ok(())
  } else {
    Err(ForeignBinding)
  }
}

///|
// Body is borrowed separately, rather than duplicating/escaping it into this
// control projection. max_bytes is an explicit caller projection clamp, not
// another reservation or an extension of the physical body/identity ceiling.
pub fn object_mutation_projection_json(
  binding : ObjectMutationBinding,
  request : ObjectMutationRequest,
  max_bytes : Int,
) -> Result[String, ObjectRequestIssue] {
  if admit_object_mutation_request(binding, request) is Err(issue) {
    return Err(issue)
  }
  if max_bytes < 1 {
    return Err(CapacityExceeded)
  }
  let after = match object_mutation_after(request) {
    Some(fields) => metadata_fields_json(fields)
    None => Json::null()
  }
  let behavior = match object_mutation_protocol_behavior(request) {
    Some(value) => value.to_json()
    None => Json::null()
  }
  let projection : Json = {
    "origin": "https://storage.googleapis.com",
    "method": request.verb.to_json(),
    "path": request.path.to_json(),
    "request_cid": request.cid.to_json(),
    "original_response_sha256": request.original.response_sha256.to_json(),
    "before": metadata_fields_json(object_mutation_before(request)),
    "after": after,
    "protocol_behavior": behavior,
    "operation": (match binding.kind {
      PatchMetadata => "gcs:object:metadata:update"
      DeleteObject => "gcs:object:delete"
    }).to_json(),
    "has_body": (binding.kind == PatchMetadata).to_json(),
  }
  mutation_json(projection, max_bytes, binding.limits.metadata)
}

///|
pub fn object_mutation_changes_json(
  binding : ObjectMutationBinding,
  request : ObjectMutationRequest,
) -> Result[String, ObjectRequestIssue] {
  admit_object_mutation_request(binding, request).map(_ => {
    request.authored_changes
  })
}

///|
pub fn object_mutation_body_for(
  binding : ObjectMutationBinding,
  request : ObjectMutationRequest,
) -> Result[String, ObjectRequestIssue] {
  admit_object_mutation_request(binding, request).map(_ => request.body)
}

///|
// Initial capture reuses the original before-GET; apply still reads/rechecks
// current metadata through its separate approved path. The guard is the CID
// of those retained response bytes, not a generation-only or authority proof.
// Project only the checked fields changed by this PATCH, as the existing
// Mapping Preview does. Json fields retain the Common Value envelope.
pub fn object_metadata_patch_effect_target_json(
  binding : ObjectMutationBinding,
  request : ObjectMutationRequest,
  max_bytes : Int,
) -> Result[String, ObjectRequestIssue] {
  if admit_object_mutation_request(binding, request) is Err(issue) {
    return Err(issue)
  }
  if binding.kind != PatchMetadata || request.verb != "PATCH" {
    return Err(InvalidBinding)
  }
  if max_bytes < 1 {
    return Err(CapacityExceeded)
  }
  guard request.marker is Some(marker) else { return Err(InvalidChanges) }
  let (content_type, metadata, changes_wire) = match
    admit_object_metadata_patch_input(
      binding,
      @utf8.encode(request.authored_changes),
      marker,
      true,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // This String was emitted by the same bounded request owner and contains
  // only the checked field names, optional text and a one-level string map.
  // Retain no new Ref or reconstructed metadata/permission original here.
  let changes = @json.parse(changes_wire) catch {
    _ => return Err(InvalidChanges)
  }
  let fields = object_metadata_fields(request.original)
  let before : Map[String, Json] = Map([])
  if content_type is Some(_) {
    before["content_type"] = match fields.content_type {
      Some(text) => text.to_json()
      None => Json::null()
    }
  }
  if metadata is Some(_) {
    before["metadata"] = match fields.metadata {
      None => Json::null()
      Some(entries) => {
        let values : Map[String, Json] = Map([])
        for (name, value) in entries {
          values[name] = value.to_json()
        }
        { "$json": Json::object(values) }
      }
    }
  }
  mutation_json(
    {
      "identity": fields.name.to_json(),
      "versionCid": ("sha256:" + request.original.response_sha256).to_json(),
      "before": Json::object(before),
      "after": changes,
      "value": changes,
      "requestCid": request.cid.to_json(),
      "protocol_behavior": "assign_original_request_marker:actql-request",
    },
    max_bytes,
    binding.limits.metadata,
  )
}
