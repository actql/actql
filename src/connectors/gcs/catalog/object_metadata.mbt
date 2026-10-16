// Provider data only. The existing Source and Effect owners still authenticate
// Resources, authorize I/O, retain the original observation and settle custody.

///|
pub(all) struct ObjectMetadataLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_metadata_entries : Int
}

///|
pub(all) enum ObjectMetadataIssue {
  InvalidLimits
  BudgetExceeded
  InvalidMetadata
  ObjectMismatch
} derive(Eq, Debug)

///|
// Decimal provider integers remain Int64, never a binary64 intermediate.
// This detached view is DATA, not a ResourceRef or a mutation permission.
pub(all) struct ObjectMetadataFields {
  bucket : String
  name : String
  generation : Int64
  metageneration : Int64
  size : Int64
  content_type : String?
  content_encoding : String?
  storage_class : String?
  updated : String?
  md5 : String?
  crc32c : String?
  metadata : Array[(String, String)]?
}

///|
pub struct ObjectMetadata {
  fields : ObjectMetadataFields
  response_sha256 : String
}

///|
fn metadata_text(
  object : @decode.ObjectView,
  name : String,
  maximum : Int,
  empty? : Bool = false,
) -> String? {
  guard @decode.lookup(object, name) is Some(value) &&
    @decode.text(value) is Ok(value) &&
    (empty || !value.is_empty()) &&
    @utf8.encode(value).length() <= maximum else {
    return None
  }
  Some(value)
}

///|
fn optional_metadata_text(
  object : @decode.ObjectView,
  name : String,
  maximum : Int,
) -> Result[String?, ObjectMetadataIssue] {
  if @decode.lookup(object, name) is None {
    return Ok(None)
  }
  match metadata_text(object, name, maximum, empty=true) {
    Some(value) => Ok(Some(value))
    None => Err(InvalidMetadata)
  }
}

///|
fn metadata_integer(
  object : @decode.ObjectView,
  name : String,
  positive~ : Bool,
) -> Int64? {
  guard @decode.lookup(object, name) is Some(value) &&
    @decode.text(value) is Ok(text) &&
    @decode.decimal_int64(value) is Ok(integer) &&
    integer >= (if positive { 1L } else { 0L }) &&
    integer.to_string() == text else {
    return None
  }
  Some(integer)
}

///|
fn custom_metadata(
  object : @decode.ObjectView,
  limits : ObjectMetadataLimits,
) -> Result[Array[(String, String)]?, ObjectMetadataIssue] {
  guard @decode.lookup(object, "metadata") is Some(value) else {
    return Ok(None)
  }
  guard @decode.object_length(value) is Some(count) else {
    return Err(InvalidMetadata)
  }
  if count > limits.max_metadata_entries {
    return Err(BudgetExceeded)
  }
  let entries = []
  for index in 0..<count {
    guard @decode.field_at(value, index) is Some((key, value)) &&
      @decode.text(value) is Ok(text) else {
      return Err(InvalidMetadata)
    }
    // Custom metadata is opaque provider DATA. Do not NFC-normalize keys or
    // values, convert newlines, or use an absent/null fallback.
    entries.push((key, text))
  }
  Ok(Some(entries))
}

///|
// Admit one complete original object response before it can be used for a
// listing row or conditional mutation. Strict bounded parsing rejects repeated
// keys and malformed UTF-8. The response digest identifies only these bytes;
// it is not an Effect receipt, Store ACK, original-resource issuer or grant.
pub fn admit_object_metadata(
  bytes : Bytes,
  expected_bucket : String,
  expected_prefix : String,
  expected_name : String?,
  limits : ObjectMetadataLimits,
) -> Result[ObjectMetadata, ObjectMetadataIssue] {
  if limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_metadata_entries < 0 {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  let parsed = match
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidMetadata
        },
      )
  }
  let root = match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        if issue.kind is @decode.BudgetExceeded {
          BudgetExceeded
        } else {
          InvalidMetadata
        },
      )
  }
  guard @decode.open_object(root) is Ok(object) &&
    metadata_text(object, "bucket", 222) is Some(bucket) &&
    metadata_text(object, "name", 1024) is Some(name) &&
    metadata_integer(object, "generation", positive=true) is Some(generation) &&
    metadata_integer(object, "metageneration", positive=true)
    is Some(metageneration) &&
    metadata_integer(object, "size", positive=false) is Some(size) else {
    return Err(InvalidMetadata)
  }
  if bucket != expected_bucket ||
    !name.has_prefix(expected_prefix) ||
    (expected_name is Some(expected) && name != expected) {
    return Err(ObjectMismatch)
  }
  let content_type = match
    optional_metadata_text(object, "contentType", limits.max_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let content_encoding = match
    optional_metadata_text(object, "contentEncoding", limits.max_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let storage_class = match
    optional_metadata_text(object, "storageClass", limits.max_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let updated = match
    optional_metadata_text(object, "updated", limits.max_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let md5 = match optional_metadata_text(object, "md5Hash", limits.max_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let crc32c = match
    optional_metadata_text(object, "crc32c", limits.max_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let metadata = match custom_metadata(object, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    fields: {
      bucket,
      name,
      generation,
      metageneration,
      size,
      content_type,
      content_encoding,
      storage_class,
      updated,
      md5,
      crc32c,
      metadata,
    },
    response_sha256: @sha.hex(bytes),
  })
}

///|
pub fn object_metadata_fields(value : ObjectMetadata) -> ObjectMetadataFields {
  {
    ..value.fields,
    metadata: value.fields.metadata.map(entries => entries.copy()),
  }
}

///|
pub fn object_metadata_response_sha256(value : ObjectMetadata) -> String {
  value.response_sha256
}

///|
pub fn object_metadata_version(value : ObjectMetadata) -> String {
  value.fields.generation.to_string()
}
