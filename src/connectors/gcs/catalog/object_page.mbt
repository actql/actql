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

///|
// Detached Source DATA, not issued Resource authority. The installed Source
// supplies its original ResourceRef beside this row. Signed Int64s use the
// existing Decimal(19,0) textual admission, never binary64 or a String field
// contract. RowSource consumes raw Source DATA: metadata is an ordinary object,
// not the exported Value wire's $json envelope.
pub fn object_metadata_page_row_json(
  page : ObjectMetadataPage,
  index : Int,
  max_bytes : Int,
  limits : ObjectMetadataLimits,
) -> Result[String, ObjectMetadataIssue] {
  guard object_metadata_page_at(page, index) is Some(fields) else {
    return Err(InvalidMetadata)
  }
  if max_bytes < 1 ||
    limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_metadata_entries < 0 {
    return Err(InvalidLimits)
  }
  if fields.metadata is Some(entries) &&
    entries.length() > limits.max_metadata_entries {
    return Err(BudgetExceeded)
  }
  let row : Map[String, Json] = {
    "version": fields.generation.to_string().to_json(),
    "name": fields.name.to_json(),
    "size": fields.size.to_string().to_json(),
    "generation": fields.generation.to_string().to_json(),
    "metageneration": fields.metageneration.to_string().to_json(),
  }
  for
    (name, value) in [
      ("content_type", fields.content_type),
      ("storage_class", fields.storage_class),
      ("md5", fields.md5),
      ("crc32c", fields.crc32c),
    ] {
    row[name] = match value {
      Some(text) => text.to_json()
      None => Json::null()
    }
  }
  row["updated"] = match fields.updated {
    None => Json::null()
    Some(text) => {
      guard object_source_timestamp(text) is Some(canonical) else {
        return Err(InvalidMetadata)
      }
      canonical.to_json()
    }
  }
  row["metadata"] = match fields.metadata {
    None => Json::null()
    Some(entries) => {
      let values : Map[String, Json] = Map([])
      for (name, value) in entries {
        values[name] = value.to_json()
      }
      Json::object(values)
    }
  }
  mutation_json(Json::object(row), max_bytes, limits).map_err(_ => {
    BudgetExceeded
  })
}

///|
// RFC 3339 provider text becomes the same UTC instant in the existing
// exact Timestamp carrier. Preserve up to nine fractional digits without binary64,
// rounding or a Host Date. The retained physical report is independent.
// An unrepresentable instant refuses.
pub fn object_source_timestamp(text : String) -> String? {
  if text.length() < 20 || text.length() > 35 {
    return None
  }
  let mut position = 19
  let mut fraction = ""
  if text[position] == '.' {
    position += 1
    let start = position
    while position < text.length() &&
          text[position] >= '0' &&
          text[position] <= '9' {
      position += 1
    }
    if position == start || position - start > 9 {
      return None
    }
    fraction = text[start:position].to_owned()
  }
  let mut nanoseconds = 0
  for unit in fraction {
    nanoseconds = nanoseconds * 10 + unit.to_int() - 48
  }
  for _ in fraction.length()..<9 {
    nanoseconds *= 10
  }
  // Validate the original local calendar fields separately from the exact
  // fraction. Offset arithmetic uses floored seconds, including before epoch.
  let local_spelling = text[:19].to_owned() + ".000Z"
  guard @admitted.timestamp_instant(local_spelling) is Some(instant) else {
    return None
  }
  let zone = text[position:].to_owned()
  if zone == "Z" {
    return @admitted.epoch_parts_timestamp(instant.seconds, nanoseconds)
  }
  if zone.length() != 6 || (zone[0] != '+' && zone[0] != '-') || zone[3] != ':' {
    return None
  }
  for index in [1, 2, 4, 5] {
    if zone[index] < '0' || zone[index] > '9' {
      return None
    }
  }
  let hours = (zone[1].to_int() - 48) * 10 + zone[2].to_int() - 48
  let minutes = (zone[4].to_int() - 48) * 10 + zone[5].to_int() - 48
  if hours > 23 || minutes > 59 {
    return None
  }
  let offset = (hours * 60 + minutes).to_int64() * 60L
  @admitted.epoch_parts_timestamp(
    if zone[0] == '+' {
      instant.seconds - offset
    } else {
      instant.seconds + offset
    },
    nanoseconds,
  )
}

///|
// The original typed Request may narrow the installed scope, never widen it.
// Absence/SQL NULL select that installed prefix; no glob or name normalization
// is inferred from arbitrary strings or a later provider result.
pub fn object_listing_prefix(
  installed_prefix : String,
  request : Bytes,
  limits : ObjectMetadataLimits,
) -> Result[String, ObjectMetadataIssue] {
  if @scalar.admit_utf8_length(installed_prefix, 1024) is Err(_) {
    return Err(ObjectMismatch)
  }
  let root = match metadata_cursor(request, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @decode.closed_object(root, ["prefix"]) is Ok(object) else {
    return Err(InvalidMetadata)
  }
  let prefix = match @decode.lookup(object, "prefix") {
    None => installed_prefix
    Some(value) if @decode.is_null(value) => installed_prefix
    Some(value) =>
      match @decode.text(value) {
        Ok(prefix) => prefix
        Err(_) => return Err(InvalidMetadata)
      }
  }
  if !prefix.has_prefix(installed_prefix) ||
    @scalar.admit_utf8_length(prefix, 1024) is Err(_) {
    Err(ObjectMismatch)
  } else {
    Ok(prefix)
  }
}
