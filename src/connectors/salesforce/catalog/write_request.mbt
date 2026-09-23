///|
pub(all) enum WriteTargetValue {
  NoWriteTarget
  RecordId(String)
  ExternalText(String)
  ExternalInt(Int)
} derive(Eq, Debug)

///|
pub(all) struct WriteRequestLimits {
  max_path_bytes : Int
  max_target_bytes : Int
  max_body_bytes : Int
}

///|
pub(all) enum WriteRequestIssue {
  InvalidLimits
  InvalidVersion
  InvalidTarget
  TargetTypeMismatch
  InvalidUnicode
  CapacityExceeded
  InvalidOrigin
  Encoding
} derive(Eq, Debug)

///|
/// Provider request material only; this is not a dispatch permit. Effect
/// preview, apply admission, current grant, and durable intent come first.
pub struct SingleWriteRequest {
  verb : String
  path : String
  body : String
  kind : WriteSingleKind
  projection : WriteProjection
}

///|
pub fn single_write_request_method(value : SingleWriteRequest) -> String {
  value.verb
}

///|
pub fn single_write_request_path(value : SingleWriteRequest) -> String {
  value.path
}

///|
pub fn single_write_request_body(value : SingleWriteRequest) -> String {
  value.body
}

///|
pub fn single_write_request_kind(value : SingleWriteRequest) -> WriteSingleKind {
  value.kind
}

///|
/// Grant operations are distinct so a read or another mutation cannot use
/// this request's credential authority.
pub fn single_write_request_grant_operation(
  value : SingleWriteRequest,
) -> String {
  match value.kind {
    SingleCreate => "salesforce:record:create"
    SingleUpdateById(_) => "salesforce:record:update"
    SingleUpsert => "salesforce:record:upsert"
  }
}

///|
/// A current Catalog observation must still admit the exact fields and
/// operation from which this immutable request was constructed.
pub fn recheck_single_write_request(
  value : SingleWriteRequest,
  current : CatalogObservation,
) -> Result[Unit, WriteProjectionIssue] {
  recheck_write_projection(value.projection, current)
}

///|
/// The historical sync dispatch is not the mutation dispatch. The latter
/// must be a valid exact CID and is separately checked by credential use.
pub fn single_write_request_matches_site_scope(
  value : SingleWriteRequest,
  tenant : String,
  principal : String,
  environment : String,
  site_key : String,
  site_generation : Int,
  connector_registration : String,
  connector_revision : String,
  resource_origin : String,
  run_invocation_cid : String,
  dispatch_request_cid : String,
) -> Bool {
  let binding = value.projection.binding
  binding.tenant == tenant &&
  binding.principal == principal &&
  binding.environment == environment &&
  binding.site_key == site_key &&
  binding.site_generation == site_generation &&
  binding.connector_registration == connector_registration &&
  binding.connector_revision == connector_revision &&
  binding.resource_origin == resource_origin &&
  binding.run_invocation_cid == run_invocation_cid &&
  observation_cid(dispatch_request_cid)
}

///|
/// The exact provider origin and outbound REST bytes form the immutable
/// request identity retained by the common Effect ledger before dispatch.
pub fn single_write_request_cid(
  value : SingleWriteRequest,
  resource_origin : String,
  max_wire_bytes : Int,
) -> Result[String, WriteRequestIssue] {
  if max_wire_bytes < 1 || max_wire_bytes > 1000000 {
    return Err(InvalidLimits)
  }
  if !resource_origin.has_prefix("https://") || resource_origin.length() <= 8 {
    return Err(InvalidOrigin)
  }
  let writer = @encode.hashing_writer(max_wire_bytes, 16, 2) catch {
    _ => return Err(Encoding)
  }
  let digest = try {
    @encode.begin_object(writer)
    @encode.key(writer, "body")
    @encode.string_value(writer, value.body)
    @encode.key(writer, "method")
    @encode.string_value(writer, value.verb)
    @encode.key(writer, "path")
    @encode.string_value(writer, value.path)
    @encode.key(writer, "resource_origin")
    @encode.string_value(writer, resource_origin)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-salesforce-rest-request/0.1")
    @encode.end_object(writer)
    @encode.finish_hash(writer)
  } catch {
    _ => return Err(Encoding)
  }
  Ok("sha256:" + digest)
}

///|
fn write_record_id_valid(id : String) -> Bool {
  if id.length() != 15 && id.length() != 18 {
    return false
  }
  for character in id.iter() {
    if !((character >= 'A' && character <= 'Z') ||
      (character >= 'a' && character <= 'z') ||
      (character >= '0' && character <= '9')) {
      return false
    }
  }
  true
}

///|
fn write_api_major(api_version : String) -> Int? {
  if api_version.length() > 10 || !query_api_version_valid(api_version) {
    return None
  }
  let mut major = 0
  for index = 1; index < api_version.length(); index = index + 1 {
    let digit = api_version[index]
    if digit == '.' {
      break
    }
    major = major * 10 + digit.to_int() - '0'.to_int()
  }
  Some(major)
}

///|
fn percent_encoded_target(
  value : String,
  max_bytes : Int,
) -> Result[String, WriteRequestIssue] {
  if value.is_empty() || value.length() > max_bytes {
    return Err(InvalidTarget)
  }
  let normalized = match @canonical.normalize_nfc(value) {
    Ok(text) => text
    Err(_) => return Err(InvalidUnicode)
  }
  match @scalar.admit_utf8_length(normalized, max_bytes) {
    Ok(_) => ()
    Err(@scalar.MalformedUtf16(_)) => return Err(InvalidUnicode)
    Err(_) => return Err(CapacityExceeded)
  }
  let bytes = @utf8.encode(normalized)
  let out = StringBuilder()
  let hex = "0123456789ABCDEF"
  let mut used = 0
  for byte in bytes {
    let n = byte.to_int()
    let unreserved = (n >= 65 && n <= 90) ||
      (n >= 97 && n <= 122) ||
      (n >= 48 && n <= 57) ||
      n == 45 ||
      n == 46 ||
      n == 95 ||
      n == 126
    let charge = if unreserved { 1 } else { 3 }
    if charge > max_bytes - used {
      return Err(CapacityExceeded)
    }
    used += charge
    if unreserved {
      out.write_char(n.to_char().unwrap())
    } else {
      out.write_char('%')
      out.write_char(hex[n >> 4].to_int().to_char().unwrap())
      out.write_char(hex[n & 15].to_int().to_char().unwrap())
    }
  }
  Ok(out.to_string())
}

///|
pub fn prepare_single_write_request(
  body : WriteBody,
  api_version : String,
  target : WriteTargetValue,
  limits : WriteRequestLimits,
) -> Result[SingleWriteRequest, WriteRequestIssue] {
  if limits.max_path_bytes < 1 ||
    limits.max_target_bytes < 1 ||
    limits.max_body_bytes < 1 {
    return Err(InvalidLimits)
  }
  guard write_api_major(api_version) is Some(major) else {
    return Err(InvalidVersion)
  }
  let projection = body.projection
  if projection.operation is WriteUpsertByExternalId(_) {
    if major < 46 {
      return Err(InvalidVersion)
    }
  }
  let prefix = "/services/data/" +
    api_version +
    "/sobjects/" +
    projection.resource +
    "/"
  let (verb, suffix, kind) = match (projection.operation, target) {
    (WriteCreate, NoWriteTarget) => ("POST", "", SingleCreate)
    (WriteUpdateById, RecordId(id)) => {
      if !write_record_id_valid(id) {
        return Err(InvalidTarget)
      }
      ("PATCH", id, SingleUpdateById(id))
    }
    (WriteUpsertByExternalId(name), ExternalText(value)) => {
      guard projection.external_target is Some(field) else {
        return Err(InvalidTarget)
      }
      if field.native_type != "string" && field.native_type != "email" {
        return Err(TargetTypeMismatch)
      }
      let encoded = match
        percent_encoded_target(value, limits.max_target_bytes) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      ("PATCH", name + "/" + encoded, SingleUpsert)
    }
    (WriteUpsertByExternalId(name), ExternalInt(value)) => {
      guard projection.external_target is Some(field) else {
        return Err(InvalidTarget)
      }
      if field.native_type != "int" {
        return Err(TargetTypeMismatch)
      }
      let rendered = value.to_string()
      if rendered.length() > limits.max_target_bytes {
        return Err(CapacityExceeded)
      }
      ("PATCH", name + "/" + rendered, SingleUpsert)
    }
    _ => return Err(InvalidTarget)
  }
  if suffix.length() > limits.max_path_bytes - prefix.length() {
    return Err(CapacityExceeded)
  }
  let text = body.json
  match @scalar.admit_utf8_length(text, limits.max_body_bytes) {
    Ok(_) => ()
    Err(@scalar.MalformedUtf16(_)) => return Err(InvalidUnicode)
    Err(_) => return Err(CapacityExceeded)
  }
  Ok({ verb, path: prefix + suffix, body: text, kind, projection, })
}
