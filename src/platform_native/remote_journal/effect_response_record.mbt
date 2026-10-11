///|
fn effect_response_cid_valid(use_cid : String) -> Bool {
  use_cid.length() == 71 &&
  use_cid.has_prefix("sha256:") &&
  use_cid
  .unsafe_substring(start=7, end=use_cid.length())
  .iter()
  .all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
}

///|
/// The existing physical response framing is shared by original Local and
/// Site journals. Only formal identity, status and an exact byte digest are
/// framed; response data is neither parsed nor normalized. The caller checks
/// original dispatch custody and holds its existing storage transaction.
pub fn effect_response_record_metadata(
  response : NativeEffectSavedResponse,
  max_body_bytes : Int64,
) -> Bytes? {
  if max_body_bytes < 0L ||
    response.body.length().to_int64() > max_body_bytes ||
    !effect_response_cid_valid(response.credential_use_cid) ||
    response.status_code < 100 ||
    response.status_code > 599 {
    return None
  }
  Some(
    @utf8.encode(
      response.credential_use_cid +
      "\n" +
      response.status_code.to_string() +
      "\n" +
      effect_response_body_digest(response.body),
    ),
  )
}

///|
/// Validate the same physical record without copying its payload or granting
/// evidence access. Storage callers retain the original bytes and budget.
pub fn effect_response_record_fields(
  metadata : Bytes,
  body : Bytes,
  max_body_bytes : Int64,
) -> (String, Int)? {
  if max_body_bytes < 0L ||
    body.length().to_int64() > max_body_bytes ||
    metadata.length() != 140 {
    return None
  }
  let text = @utf8.decode(metadata) catch { _ => return None }
  let parts = text.split("\n").map(value => value.to_owned()).to_array()
  guard parts.length() == 3 else { return None }
  let status = @string.parse_int(parts[1]) catch { _ => return None }
  if !effect_response_cid_valid(parts[0]) ||
    status < 100 ||
    status > 599 ||
    status.to_string() != parts[1] ||
    effect_response_body_digest(body) != parts[2] {
    return None
  }
  Some((parts[0], status))
}
