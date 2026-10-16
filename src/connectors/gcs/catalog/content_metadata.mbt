// A versioned Content read uses the original provider bytes, not the logical
// object-row projection (which has a different Int64/custom-metadata schema).
// This admission issues DATA only: capture and physical custody stay with the
// existing RowRun and installed Source.

///|
pub(all) enum ContentMetadataIssue {
  InvalidMetadata
  MetadataMismatch
  RepresentationUnsupported
  InvalidDigest
} derive(Eq, Debug)

///|
fn content_decimal(text : String, positive~ : Bool) -> Bool {
  !text.is_empty() &&
  text.length() <= 20 &&
  text.iter().all(character => character >= '0' && character <= '9') &&
  ((text == "0" && !positive) || !text.has_prefix("0"))
}

///|
fn content_digest(text : String, expected : Int) -> Bool {
  try {
    let bytes = @base64.decode(text[:])
    bytes.length() == expected && @base64.encode(bytes.view()) == text
  } catch {
    _ => false
  }
}

///|
// The complete original bounded parser rejects duplicate keys, including
// escaped-equivalent keys. Unknown provider fields are not normalized into
// replacement metadata or interpreted as authority.
pub fn content_metadata_json(
  bytes : Bytes,
  bucket : String,
  name : String,
  generation : String,
  max_content_bytes : Int64,
  limits : ObjectMetadataLimits,
) -> Result[String, ContentMetadataIssue] {
  let root = match metadata_cursor(bytes, limits) {
    Ok(value) => value
    Err(_) => return Err(InvalidMetadata)
  }
  guard @decode.open_object(root) is Ok(object) else {
    return Err(MetadataMismatch)
  }
  guard metadata_text(object, "bucket", limits.max_bytes) == Some(bucket) &&
    metadata_text(object, "name", limits.max_bytes) == Some(name) &&
    metadata_text(object, "generation", limits.max_bytes) == Some(generation) &&
    metadata_text(object, "metageneration", 20) is Some(metageneration) &&
    content_decimal(metageneration, positive=true) &&
    metadata_text(object, "size", 20) is Some(size) &&
    content_decimal(size, positive=false) &&
    metadata_text(object, "contentType", 1024) is Some(media_type) &&
    upload_text(media_type, 1024) else {
    return Err(MetadataMismatch)
  }
  // Compare decimal magnitudes before converting. Arbitrary twenty-digit
  // provider text never overflows Int64 or passes through binary64.
  let maximum = max_content_bytes.to_string()
  if max_content_bytes < 0L ||
    size.length() > maximum.length() ||
    (size.length() == maximum.length() && size > maximum) {
    return Err(MetadataMismatch)
  }
  let encoding = match @decode.lookup(object, "contentEncoding") {
    None => None
    Some(value) => {
      guard @decode.text(value) is Ok(text) &&
        (text == "identity" || text == "gzip") else {
        return Err(RepresentationUnsupported)
      }
      if text == "gzip" { Some(text) } else { None }
    }
  }
  guard metadata_text(object, "crc32c", limits.max_bytes) is Some(crc32c) &&
    content_digest(crc32c, 4) else {
    return Err(InvalidDigest)
  }
  let md5 = match @decode.lookup(object, "md5Hash") {
    None => None
    Some(value) => {
      guard @decode.text(value) is Ok(text) && content_digest(text, 16) else {
        return Err(InvalidDigest)
      }
      Some(text)
    }
  }
  let fields : Map[String, Json] = {
    "bucket": bucket.to_json(),
    "objectName": name.to_json(),
    "generation": generation.to_json(),
    "metageneration": metageneration.to_json(),
    "sizeBytes": size.to_json(),
    "mediaType": media_type.to_json(),
    "crc32c": crc32c.to_json(),
  }
  if encoding is Some(value) { fields["contentEncoding"] = value.to_json() }
  if md5 is Some(value) { fields["md5"] = value.to_json() }
  // The private projection has bounded additional key spelling, not another
  // response allowance or a capacity grant. It overlaps the original bytes.
  if limits.max_bytes > 2147483391 { return Err(InvalidMetadata) }
  mutation_json(Json::object(fields), limits.max_bytes + 256, limits)
  .map_err(_ => InvalidMetadata)
}
