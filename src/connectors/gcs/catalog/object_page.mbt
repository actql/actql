// An original physical page is DATA, not a listing completion, issued Resource,
// read grant or mutation observation. Common retains those responsibilities.

///|
pub struct ObjectMetadataPage {
  items : Array[ObjectMetadataFields]
  next_token : String?
  response_sha256 : String
}

///|
// Flat scans do not request a delimiter or all versions. Keep unexpected prefix
// pages unavailable, not silently complete. Every physical item is checked
// before projection; host filtering cannot make an invalid item disappear.
pub fn admit_object_metadata_page(
  bytes : Bytes,
  expected_bucket : String,
  expected_prefix : String,
  max_items : Int,
  limits : ObjectMetadataLimits,
) -> Result[ObjectMetadataPage, ObjectMetadataIssue] {
  if max_items < 0 {
    return Err(InvalidLimits)
  }
  if expected_bucket.is_empty() ||
    @scalar.admit_utf8_length(expected_bucket, 222) is Err(_) ||
    @scalar.admit_utf8_length(expected_prefix, 1024) is Err(_) {
    return Err(ObjectMismatch)
  }
  let root = match metadata_cursor(bytes, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @decode.open_object(root) is Ok(object) &&
    metadata_text(object, "kind", 32) is Some("storage#objects") else {
    return Err(InvalidMetadata)
  }
  if @decode.lookup(object, "prefixes") is Some(prefixes) {
    guard @decode.array_length(prefixes) is Some(0) else {
      return Err(InvalidMetadata)
    }
  }
  let next_token = match @decode.lookup(object, "nextPageToken") {
    None => None
    Some(_) => {
      guard metadata_text(object, "nextPageToken", 8192) is Some(token) &&
        token
        .iter()
        .all(character => character.to_int() >= 32 && character.to_int() != 127) else {
        return Err(InvalidMetadata)
      }
      Some(token)
    }
  }
  let items = []
  if @decode.lookup(object, "items") is Some(observed) {
    guard @decode.array_length(observed) is Some(count) else {
      return Err(InvalidMetadata)
    }
    if count > max_items {
      return Err(BudgetExceeded)
    }
    for index in 0..<count {
      let fields = match
        metadata_fields_from_cursor(
          @decode.element_at(observed, index).unwrap(),
          expected_bucket,
          expected_prefix,
          None,
          limits,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      items.push(fields)
    }
  }
  Ok({ items, next_token, response_sha256: @sha.hex(bytes), })
}

///|
pub fn object_metadata_page_count(page : ObjectMetadataPage) -> Int {
  page.items.length()
}

///|
// Detached logical DATA hides only the reserved exact protocol key. It does
// not expose internal backing or issue the member as an ObjectMetadata handle
// for mutation: its original response is the whole list page, not object GET.
pub fn object_metadata_page_at(
  page : ObjectMetadataPage,
  index : Int,
) -> ObjectMetadataFields? {
  if index < 0 || index >= page.items.length() {
    return None
  }
  let fields = page.items[index]
  Some({ ..fields, metadata: logical_metadata(fields.metadata), })
}

///|
pub fn object_metadata_page_next_token(page : ObjectMetadataPage) -> String? {
  page.next_token
}

///|
pub fn object_metadata_page_response_sha256(
  page : ObjectMetadataPage,
) -> String {
  page.response_sha256
}
