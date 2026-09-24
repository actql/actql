///|
/// The logical request scope is shared by Client admission and Effect
/// dispatch. Its preimage contains no physical Run, Site, or attempt identity.
pub(all) enum ScopeIssue {
  InvalidLimits
  InvalidAuthorityScope
  InvalidCallerRequest
  Encoding
} derive(Eq, Debug)

///|
fn valid_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index = 7; index < 71; index = index + 1 {
    let digit = value[index]
    if !((digit >= '0' && digit <= '9') || (digit >= 'a' && digit <= 'f')) {
      return false
    }
  }
  true
}

///|
/// Reject noncanonical caller IDs before an authority binds a durable key.
/// The byte limit is supplied by the owning public profile.
pub fn prepare_scope_cid(
  authority_scope_cid : String,
  caller_request_id : String,
  max_caller_bytes : Int,
) -> Result[String, ScopeIssue] {
  if max_caller_bytes < 1 || max_caller_bytes > 1000000 {
    return Err(InvalidLimits)
  }
  if !valid_cid(authority_scope_cid) {
    return Err(InvalidAuthorityScope)
  }
  if caller_request_id.is_empty() ||
    caller_request_id.length() > max_caller_bytes ||
    @utf8.encode(caller_request_id).length() > max_caller_bytes {
    return Err(InvalidCallerRequest)
  }
  match @canonical.normalize_nfc_lf(caller_request_id) {
    Ok(normalized) if normalized == caller_request_id => ()
    _ => return Err(InvalidCallerRequest)
  }
  for index = 0; index < caller_request_id.length(); index = index + 1 {
    let unit = caller_request_id[index].to_int()
    if unit < 32 || unit == 127 {
      return Err(InvalidCallerRequest)
    }
  }
  let writer = @encode.hashing_writer(max_caller_bytes * 6 + 256, 4, 1) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "authority_scope_cid")
    @encode.string_value(writer, authority_scope_cid)
    @encode.key(writer, "caller_request_id")
    @encode.string_value(writer, caller_request_id)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-logical-request/0.1")
    @encode.end_object(writer)
    Ok("sha256:" + @encode.finish_hash(writer))
  } catch {
    _ => Err(Encoding)
  }
}
