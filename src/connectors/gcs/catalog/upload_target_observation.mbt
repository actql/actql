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
  if headers.length() > 3 {
    return Err(CapacityExceeded)
  }
  let mut encoding : String? = None
  let mut generation : String? = None
  let mut metageneration : String? = None
  let mut header_bytes = 0
  for (key, value) in headers {
    let maximum = binding.limits.metadata.max_bytes
    let remaining = maximum - header_bytes
    match @scalar.admit_utf8_length(value, remaining) {
      Err(_) => return Err(CapacityExceeded)
      Ok(length) => header_bytes += length
    }
    match key {
      "content-encoding" if encoding is None => encoding = Some(value)
      "x-goog-generation" if generation is None => generation = Some(value)
      "x-goog-metageneration" if metageneration is None =>
        metageneration = Some(value)
      _ => return Err(InvalidInput)
    }
  }
  if encoding is Some(value) && value != "identity" {
    return Err(InvalidInput)
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
