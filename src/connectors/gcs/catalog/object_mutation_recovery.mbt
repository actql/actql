// Re-admit retained request material after the existing capture/Store Owner
// authenticates it. DATA/CIDs alone are not acquisition custody, read/write
// permission, apply-current proof, a dispatch claim, or a provider receipt.

///|
// Ordinary Effect changes use the existing Value wire; no JSON-envelope guess
// or new marker is permitted here. Raw observation bytes and their separately
// retained guard are both mandatory: the request CID does not include that raw
// response hash, so equal parsed fields/versions cannot replace these bytes.
pub fn restore_object_mutation_value_wire(
  binding : ObjectMutationBinding,
  expected_name : String,
  response_status : Int,
  response_headers : Array[(String, String)],
  response_bytes : Bytes,
  response_sha256 : String,
  changes : Bytes,
  body : String,
  request_cid : String,
) -> Result[ObjectMutationRequest, ObjectRequestIssue] {
  let limits = binding.limits
  if response_bytes.length() > limits.metadata.max_bytes ||
    changes.length() > limits.metadata.max_bytes ||
    @scalar.admit_utf8_length(body, limits.max_body_bytes) is Err(_) {
    return Err(CapacityExceeded)
  }
  if expected_name.is_empty() ||
    @scalar.admit_utf8_length(expected_name, limits.metadata.max_bytes)
    is Err(_) ||
    !mutation_cid(request_cid) ||
    response_sha256.length() != 64 ||
    !mutation_cid("sha256:" + response_sha256) {
    return Err(InvalidBinding)
  }
  if @sha.hex(response_bytes) != response_sha256 {
    return Err(StaleObservation)
  }
  let original = match
    admit_object_mutation_target_observation(
      binding, expected_name, response_status, response_bytes, response_headers,
    ) {
    Ok(value) => value
    Err(CapacityExceeded) | Err(Metadata(BudgetExceeded)) =>
      return Err(CapacityExceeded)
    Err(InvalidName) | Err(Metadata(ObjectMismatch)) =>
      return Err(ForeignBinding)
    Err(_) => return Err(InvalidChanges)
  }
  if original.response_sha256 != response_sha256 {
    return Err(StaleObservation)
  }
  let request = match binding.kind {
    PatchMetadata => {
      guard mutation_body_marker(binding, body) is Some(marker) else {
        return Err(InvalidChanges)
      }
      match
        prepare_object_metadata_patch_value_wire(
          binding, original, changes, marker,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
    }
    DeleteObject => {
      if changes != b"{}" || body != "" {
        return Err(InvalidChanges)
      }
      match prepare_object_delete(binding, original) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
    }
  }
  // Recheck exact authored/canonical and physical material independently. The
  // returned request belongs to this actual binding, never an old pointer
  // reconstructed by CID lookup or a newly authorized physical operation.
  if @utf8.encode(request.authored_changes) != changes ||
    request.body != body ||
    request.cid != request_cid {
    return Err(InvalidChanges)
  }
  Ok(request)
}
