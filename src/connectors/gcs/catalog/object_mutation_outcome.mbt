// Provider consistency only. The existing Effect Ledger must authenticate the
// original dispatch and retained direct response before using this projection.
// A later GET/404 never proves a delete or authorizes another physical send.

///|
pub(all) enum ObjectMutationOutcome {
  Applied
  Conflict
  Unknown
} derive(Eq, Debug)

///|
fn mutation_request_marker(request : ObjectMutationRequest) -> String? {
  // Reuse the bounded decoder on the original sealed request, not current
  // configuration or a caller's expected marker. No new record field/issuer.
  guard metadata_cursor(@utf8.encode(request.body), {
      ..request.binding.limits.metadata,
      max_bytes: request.binding.limits.max_body_bytes,
    })
    is Ok(root) &&
    @decode.open_object(root) is Ok(object) &&
    @decode.required(object, "metadata") is Ok(metadata) &&
    @decode.open_object(metadata) is Ok(metadata) &&
    metadata_text(metadata, "actql-request", 71) is Some(marker) &&
    mutation_cid(marker) else {
    return None
  }
  Some(marker)
}

///|
pub fn object_mutation_response_matches(
  binding : ObjectMutationBinding,
  request : ObjectMutationRequest,
  observed : ObjectMetadata,
) -> Bool {
  if !physical_equal(binding, request.binding) || binding.kind != PatchMetadata {
    return false
  }
  guard request.logical_after is Some(expected) &&
    mutation_request_marker(request) is Some(marker) else {
    return false
  }
  let before = request.original.fields
  let actual = observed.fields
  // Metadata updates do not replace object bytes/generation/storage class.
  // Only selected user properties change; the original response may advance
  // metageneration but cannot keep or move behind the captured version.
  if actual.bucket != before.bucket ||
    actual.name != before.name ||
    actual.generation != before.generation ||
    actual.metageneration <= before.metageneration ||
    actual.size != before.size ||
    actual.content_type != expected.content_type ||
    actual.content_encoding != before.content_encoding ||
    (before.storage_class is Some(value) && actual.storage_class != Some(value)) ||
    (before.md5 is Some(value) && actual.md5 != Some(value)) ||
    (before.crc32c is Some(value) && actual.crc32c != Some(value)) {
    return false
  }
  let intended = expected.metadata.unwrap_or([]).copy()
  let received = logical_metadata(actual.metadata).unwrap_or([])
  intended.sort_by((left, right) => left.0.lexical_compare(right.0))
  received.sort_by((left, right) => left.0.lexical_compare(right.0))
  intended == received &&
  actual.metadata.unwrap_or([]).any(entry => entry == ("actql-request", marker))
}

///|
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
  if binding.kind == DeleteObject {
    // An authenticated original empty DELETE response is confirmation, not
    // evidence inferred from subsequent object absence. Lost reply stays
    // Unknown, including after a 404 from any later observation.
    return Ok(if status == 204 && body.is_empty() { Applied } else { Unknown })
  }
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
            "message": "The original GCS mutation precondition failed",
          },
        },
      }
    Unknown => { "kind": "provider-response" }
  }
  mutation_json(projection, max_bytes, binding.limits.metadata)
}
