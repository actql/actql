// The existing GCS metadata representation's bounded header interpretation.
// Physical acquisition, response custody and permission stay with their owners.

///|
fn object_target_header_versions(
  limits : ObjectMetadataLimits,
  headers : Array[(String, String)],
) -> Result[(String?, String?), ObjectUploadIssue] {
  if headers.length() > 3 {
    return Err(CapacityExceeded)
  }
  let mut encoding : String? = None
  let mut generation : String? = None
  let mut metageneration : String? = None
  let mut header_bytes = 0
  for (key, value) in headers {
    let remaining = limits.max_bytes - header_bytes
    match @scalar.admit_utf8_length(value, remaining) {
      Err(_) => return Err(CapacityExceeded)
      Ok(length) => header_bytes += length
    }
    match key {
      "content-encoding" if encoding is None => encoding = Some(value)
      "x-goog-generation" if generation is None => generation = Some(value)
      "x-goog-metageneration" if metageneration is None => metageneration = Some(value)
      _ => return Err(InvalidInput)
    }
  }
  if encoding is Some(value) && value != "identity" {
    return Err(InvalidInput)
  }
  Ok((generation, metageneration))
}
