// Before-observation DATA for the original conditional metadata/delete request.
// It is not absence, a write grant, an apply outcome or a physical cleanup ACK.

///|
pub(all) enum ObjectTargetReadIssue {
  InvalidName
  InvalidResponse
  CapacityExceeded
  Metadata(ObjectMetadataIssue)
} derive(Eq, Debug)

///|
/// Current target metadata GET, not a versioned Content request. The resulting
/// original observation supplies both version conditions of the later write.
pub fn object_mutation_metadata_path(
  binding : ObjectMutationBinding,
  name : String,
) -> Result[String, ObjectTargetReadIssue] {
  if name.is_empty() ||
    !name.has_prefix(binding.prefix) ||
    name.iter().any(c => c == '\r' || c == '\n') {
    return Err(InvalidName)
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
pub fn object_mutation_metadata_max_bytes(
  binding : ObjectMutationBinding,
) -> Int {
  binding.limits.metadata.max_bytes
}

///|
/// Admit only the original complete metadata response, preserving its exact
/// bytes/hash and target. A refused/missing read cannot invent a before row.
pub fn admit_object_mutation_target_observation(
  binding : ObjectMutationBinding,
  name : String,
  status : Int,
  body : Bytes,
  headers : Array[(String, String)],
) -> Result[ObjectMetadata, ObjectTargetReadIssue] {
  match object_mutation_metadata_path(binding, name) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let (generation, metageneration) = match
    object_target_header_versions(binding.limits.metadata, headers) {
    Ok(value) => value
    Err(CapacityExceeded) => return Err(CapacityExceeded)
    Err(_) => return Err(InvalidResponse)
  }
  if status != 200 {
    return Err(InvalidResponse)
  }
  let original = match
    admit_object_metadata(
      body,
      binding.bucket,
      binding.prefix,
      Some(name),
      binding.limits.metadata,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Metadata(issue))
  }
  if (
      generation is Some(value) &&
      value != original.fields.generation.to_string()
    ) ||
    (
      metageneration is Some(value) &&
      value != original.fields.metageneration.to_string()
    ) {
    return Err(InvalidResponse)
  }
  Ok(original)
}
