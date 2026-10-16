// Provider response interpretation only. The existing Effect Owner authenticates
// the original dispatch/response, records outcomes and preserves Unknown custody.

///|
pub(all) enum ObjectUploadOutcome {
  Applied
  Conflict
  Unknown
} derive(Eq, Debug)

///|
// Only the direct response to this conditional upload may establish conflict.
// A later metadata GET failure, missing reply or object absence cannot do so.
pub fn classify_object_upload_response(
  binding : ObjectUploadBinding,
  request : ObjectUploadRequest,
  status : Int,
  body : Bytes,
) -> Result[ObjectUploadOutcome, ObjectUploadIssue] {
  if !physical_equal(binding, request.binding) {
    return Err(ForeignBinding)
  }
  if body.length() > binding.limits.metadata.max_bytes {
    return Err(CapacityExceeded)
  }
  if status == 412 {
    return Ok(Conflict)
  }
  if status != 200 {
    return Ok(Unknown)
  }
  let observed = match
    admit_object_metadata(
      body,
      binding.bucket,
      binding.prefix,
      Some(request.before.name),
      binding.limits.metadata,
    ) {
    Ok(value) => value
    Err(BudgetExceeded) => return Err(CapacityExceeded)
    Err(_) => return Ok(Unknown)
  }
  if object_upload_response_matches(binding, request, observed) &&
    (
      observed.fields.content_encoding is None ||
      observed.fields.content_encoding == Some("identity")
    ) {
    Ok(Applied)
  } else {
    Ok(Unknown)
  }
}

///|
pub fn object_upload_response_projection_json(
  binding : ObjectUploadBinding,
  request : ObjectUploadRequest,
  status : Int,
  body : Bytes,
  max_bytes : Int,
) -> Result[String, ObjectUploadIssue] {
  if max_bytes < 1 {
    return Err(CapacityExceeded)
  }
  let outcome = match
    classify_object_upload_response(binding, request, status, body) {
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
            "message": "The original GCS upload precondition failed",
          },
        },
      }
    Unknown => { "kind": "provider-response" }
  }
  upload_json(projection, max_bytes, binding.limits.metadata)
}
