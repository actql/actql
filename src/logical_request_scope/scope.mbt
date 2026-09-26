///|
/// One canonical logical request key shared by Client ingress and Effect
/// dispatch. Intent and physical attempts have separate identities.
struct LogicalRequestScope {
  authority_scope_cid : String
  caller_request_id : String
  cid : String
} derive(Eq, Debug)

///|
pub(all) enum LogicalRequestScopeIssue {
  InvalidAuthorityScope
  InvalidCallerRequest
  InvalidLimits
  Encoding
} derive(Eq, Debug)

///|
pub fn logical_request_scope_cid(value : LogicalRequestScope) -> String {
  value.cid
}

///|
pub fn logical_request_scope_authority(value : LogicalRequestScope) -> String {
  value.authority_scope_cid
}

///|
pub fn logical_request_scope_caller_id(value : LogicalRequestScope) -> String {
  value.caller_request_id
}

///|
fn valid_scope_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index = 7; index < 71; index = index + 1 {
    let unit = value[index].to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
fn valid_caller_id(value : String, max_caller_bytes : Int) -> Bool {
  if value.is_empty() ||
    value.length() > max_caller_bytes ||
    @utf8.encode(value).length() > max_caller_bytes {
    return false
  }
  match @canonical.normalize_nfc_lf(value) {
    Ok(normalized) if normalized == value => ()
    _ => return false
  }
  for character in value.iter() {
    let unit = character.to_int()
    if unit < 32 || (unit >= 127 && unit <= 159) {
      return false
    }
  }
  true
}

///|
/// The 0.1 caller ID ceiling is 256 UTF-8 bytes. A caller may request a
/// tighter limit, but no consumer may expand the shared accepted domain.
pub fn prepare_logical_request_scope(
  authority_scope_cid : String,
  caller_request_id : String,
  max_caller_bytes : Int,
) -> Result[LogicalRequestScope, LogicalRequestScopeIssue] {
  if max_caller_bytes < 1 || max_caller_bytes > 256 {
    return Err(InvalidLimits)
  }
  if !valid_scope_cid(authority_scope_cid) {
    return Err(InvalidAuthorityScope)
  }
  if !valid_caller_id(caller_request_id, max_caller_bytes) {
    return Err(InvalidCallerRequest)
  }
  let writer = @encode.hashing_writer(1792, 4, 1) catch {
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
    Ok({
      authority_scope_cid,
      caller_request_id,
      cid: "sha256:" + @encode.finish_hash(writer),
    })
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// The Client ingress uses the same owned scope admission and CID preimage.
pub fn prepare_scope_cid(
  authority_scope_cid : String,
  caller_request_id : String,
  max_caller_bytes : Int,
) -> Result[String, LogicalRequestScopeIssue] {
  match
    prepare_logical_request_scope(
      authority_scope_cid, caller_request_id, max_caller_bytes,
    ) {
    Ok(scope) => Ok(logical_request_scope_cid(scope))
    Err(issue) => Err(issue)
  }
}
