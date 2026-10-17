// Original conditional request/response consistency. The existing Effect
// Ledger authenticates the direct response and owns settlement/Unknown.

///|
pub(all) enum ObjectMutationOutcome {
  Applied
  Conflict
  Unknown
} derive(Eq, Debug)

///|
// A later metadata read may supply correlation DATA for PATCH only. The
// original request/claim/current authority are still required by its caller;
// this function cannot authenticate that read or settle a possible dispatch.
pub fn object_mutation_response_matches(
  binding : ObjectMutationBinding,
  request : ObjectMutationRequest,
  response : ObjectMetadata,
) -> Bool {
  if !physical_equal(binding, request.binding) || binding.kind != PatchMetadata {
    return false
  }
  guard request.marker is Some(marker) &&
    request.logical_after is Some(expected) else {
    return false
  }
  let before = request.original.fields
  let fields = response.fields
  let desired = expected.metadata.unwrap_or([])
  let observed = logical_metadata(fields.metadata).unwrap_or([])
  fields.bucket == before.bucket &&
  fields.name == before.name &&
  fields.generation == before.generation &&
  fields.metageneration > before.metageneration &&
  fields.size == before.size &&
  fields.content_type == expected.content_type &&
  fields.content_encoding == before.content_encoding &&
  fields.storage_class == before.storage_class &&
  fields.md5 == before.md5 &&
  fields.crc32c == before.crc32c &&
  fields.metadata.unwrap_or([]).contains(("actql-request", marker)) &&
  observed.length() == desired.length() &&
  observed.all(entry => desired.contains(entry))
}

///|
// Only the response authenticated for this original conditional dispatch may
// establish direct conflict or DELETE success. Object absence after a lost
// DELETE response is deliberately not an input to this classifier.
pub fn classify_object_mutation_response(
  binding : ObjectMutationBinding,
  request : ObjectMutationRequest,
  status : Int,
  body : Bytes,
) -> Result[ObjectMutationOutcome, ObjectRequestIssue] {
  if !physical_equal(binding, request.binding) {
    return Err(ForeignBinding)
  }
  if body.length() > binding.limits.metadata.max_bytes {
    return Err(CapacityExceeded)
  }
  if status == 412 {
    return Ok(Conflict)
  }
  match binding.kind {
    DeleteObject =>
      Ok(if status == 204 && body.length() == 0 { Applied } else { Unknown })
    PatchMetadata => {
      if status != 200 {
        return Ok(Unknown)
      }
      let observed = match
        admit_object_metadata(
          body,
          binding.bucket,
          binding.prefix,
          Some(request.original.fields.name),
          binding.limits.metadata,
        ) {
        Ok(value) => value
        Err(BudgetExceeded) => return Err(CapacityExceeded)
        Err(_) => return Ok(Unknown)
      }
      Ok(
        if object_mutation_response_matches(binding, request, observed) {
          Applied
        } else {
          Unknown
        },
      )
    }
  }
}

///|
pub fn object_mutation_response_projection_json(
  binding : ObjectMutationBinding,
  request : ObjectMutationRequest,
  status : Int,
  body : Bytes,
  max_bytes : Int,
) -> Result[String, ObjectRequestIssue] {
  if max_bytes < 1 {
    return Err(CapacityExceeded)
  }
  let outcome = match
    classify_object_mutation_response(binding, request, status, body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let projection : Json = match outcome {
    Applied =>
      {
        "kind": "typed-success-response",
        "outcome": { "state": "applied", "result": {} },
      }
    Conflict =>
      {
        "kind": "typed-failure-response",
        "outcome": {
          "state": "failed",
          "error": {
            "code": "conflict",
            "message": "The original GCS object precondition failed",
          },
        },
      }
    Unknown => { "kind": "provider-response" }
  }
  mutation_json(projection, max_bytes, binding.limits.metadata)
}
