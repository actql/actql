// Interpret only the retained physical target response. The Credential and
// capture Owners separately authenticate its use, currentness and custody.

///|
pub fn admit_object_upload_target_observation(
  binding : ObjectUploadBinding,
  name : String,
  status : Int,
  body : Bytes,
  headers : Array[(String, String)],
) -> Result[ObjectUploadObservation, ObjectUploadIssue] {
  let (generation, metageneration) = match object_target_header_versions(
    binding.limits.metadata, headers,
  ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let observed = match
    admit_object_upload_observation(binding, name, status, body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match observed.original {
    None =>
      if generation is Some(_) || metageneration is Some(_) {
        Err(InvalidInput)
      } else {
        Ok(observed)
      }
    Some(metadata) => {
      if generation is Some(value) &&
        value != metadata.fields.generation.to_string() {
        return Err(StaleObservation)
      }
      if metageneration is Some(value) &&
        value != metadata.fields.metageneration.to_string() {
        return Err(StaleObservation)
      }
      Ok(observed)
    }
  }
}
