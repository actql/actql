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
  if limits.max_bytes < 1 || limits.max_nodes < 1 || limits.max_depth < 1 {
    return Err(InvalidLimits)
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
