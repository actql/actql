///|
/// The original public token's shape and identity, not HMAC authentication.
pub struct ClientSubmissionEpochToken {
  body : SubmissionEpoch
  authority_scope_cid : String
  tag : Bytes
  wire : String
}

///|
pub(all) enum ClientSubmissionEpochTokenIssue {
  Unverifiable
  Identity(SubmissionIdentityIssue)
}

///|
pub struct ClientSubmissionReferenceRecord {
  epoch : ClientSubmissionEpochToken
  request_id : String
  wire : String
}

///|
pub(all) enum ClientSubmissionReferenceRecordIssue {
  InvalidReference
  Encoding
  Epoch(ClientSubmissionEpochTokenIssue)
}

///|
fn submission_record_value(wire : String) -> @canonical.CanonicalValue? {
  @source.parse_json_bytes_preserving(@utf8.encode(wire), {
    max_input_bytes: 4096,
    max_nodes: 32,
    max_depth: 4,
  })
  .to_option()
  .bind(value => {
    Some(@canonical.from_source(value, 32, 4, 4096, data_keys=true)) catch {
      _ => None
    }
  })
}

///|
fn submission_record_hex(text : String) -> Bytes? {
  if text.length() != 64 {
    return None
  }
  let digit = fn(unit : UInt16) {
    let ch = unit.to_int()
    if ch >= 48 && ch <= 57 {
      Some(ch - 48)
    } else if ch >= 97 && ch <= 102 {
      Some(ch - 87)
    } else {
      None
    }
  }
  let out : Array[Byte] = []
  for i in 0..<32 {
    guard digit(text[i * 2]) is Some(a) && digit(text[i * 2 + 1]) is Some(b) else {
      return None
    }
    out.push((a * 16 + b).to_byte())
  }
  Some(Bytes::makei(32, i => out[i]))
}

///|
pub fn admit_client_submission_epoch_token(
  wire : String,
) -> Result[ClientSubmissionEpochToken, ClientSubmissionEpochTokenIssue] {
  let source = @source.parse_json_bytes_preserving(@utf8.encode(wire), {
    max_input_bytes: 4096,
    max_nodes: 32,
    max_depth: 4,
  }).to_option()
  guard source is Some(source) &&
    @decode.admit(source, {
      max_nodes: 32,
      max_depth: 4,
      max_string_bytes: 1024,
      max_total_string_bytes: 4096,
    })
    is Ok(cursor) &&
    @decode.closed_object(cursor, [
      "version", "authorityScopeCid", "epochNonce", "notBefore", "expiresAt", "authenticator",
    ])
    is Ok(object) else {
    return Err(Unverifiable)
  }
  let text = key => {
    @decode.lookup(object, key).bind(value => @decode.text(value).to_option())
  }
  let number = key => {
    @decode.lookup(object, key).bind(value => {
      @decode.finite_number(value).to_option()
    })
  }
  guard text("version") == Some("actql-submission-epoch/0.1") &&
    text("authorityScopeCid") is Some(authority) &&
    text("epochNonce") is Some(nonce) &&
    number("notBefore") is Some(before) &&
    number("expiresAt") is Some(expires) &&
    text("authenticator").bind(submission_record_hex) is Some(tag) else {
    return Err(Unverifiable)
  }
  prepare_submission_epoch(authority, nonce, before, expires)
  .map(body => { body, authority_scope_cid: authority, tag, wire, })
  .map_err(issue => Identity(issue))
}

///|
pub fn client_submission_epoch_token_body(
  value : ClientSubmissionEpochToken,
) -> SubmissionEpoch {
  value.body
}

///|
/// Original token identity only, not epoch authentication or current authority.
pub fn client_submission_epoch_token_authority_scope_cid(
  value : ClientSubmissionEpochToken,
) -> String {
  value.authority_scope_cid
}

///|
pub fn client_submission_epoch_token_tag(
  value : ClientSubmissionEpochToken,
) -> Bytes {
  value.tag
}

///|
pub fn client_submission_epoch_token_wire(
  value : ClientSubmissionEpochToken,
) -> String {
  value.wire
}

///|
/// Preserve the Native reference's original canonicalization, with no NFC or
/// newline changes. Authentication and current epoch custody stay physical.
pub fn prepare_client_submission_reference_record(
  epoch : ClientSubmissionEpochToken,
  nonce : String,
) -> Result[
  ClientSubmissionReferenceRecord,
  ClientSubmissionReferenceRecordIssue,
] {
  let request_id = match submission_request_id(epoch.body, nonce) {
    Ok(value) => value
    Err(_) => return Err(InvalidReference)
  }
  guard submission_record_value(epoch.wire) is Some(body) else {
    return Err(InvalidReference)
  }
  try {
    let writer = @encode.writer(4096, 32, 4)
    @encode.begin_object(writer)
    @encode.key(writer, "epoch")
    @canonical.emit_value(body, writer)
    @encode.key(writer, "nonce")
    @encode.string_value(writer, nonce)
    @encode.end_object(writer)
    let wire = @encode.finish(writer)
    let epoch_wire = @canonical.stringify_value(body, 4096, 32, 4)
    let epoch = match admit_client_submission_epoch_token(epoch_wire) {
      Ok(value) => value
      Err(issue) => return Err(Epoch(issue))
    }
    Ok({ epoch, request_id, wire, })
  } catch {
    _ => Err(Encoding)
  }
}

///|
pub fn admit_client_submission_reference_record(
  wire : String,
) -> Result[
  ClientSubmissionReferenceRecord,
  ClientSubmissionReferenceRecordIssue,
] {
  guard submission_record_value(wire) is Some(value) &&
    @canonical.object_field_count(value) == Some(2) &&
    @canonical.object_field(value, "epoch") is Some(epoch) &&
    @canonical.object_field(value, "nonce") is Some(@canonical.String(nonce)) else {
    return Err(InvalidReference)
  }
  let epoch_wire = @canonical.stringify_value(epoch, 4096, 32, 4) catch {
    _ => return Err(InvalidReference)
  }
  let epoch = match admit_client_submission_epoch_token(epoch_wire) {
    Ok(value) => value
    Err(issue) => return Err(Epoch(issue))
  }
  prepare_client_submission_reference_record(epoch, nonce)
}

///|
pub fn client_submission_reference_record_epoch(
  value : ClientSubmissionReferenceRecord,
) -> ClientSubmissionEpochToken {
  value.epoch
}

///|
pub fn client_submission_reference_record_request_id(
  value : ClientSubmissionReferenceRecord,
) -> String {
  value.request_id
}

///|
pub fn client_submission_reference_record_wire(
  value : ClientSubmissionReferenceRecord,
) -> String {
  value.wire
}

///|
pub fn client_submission_reference_matches_request(
  value : ClientSubmissionReferenceRecord,
  request : ClientRequestIdentity,
) -> Bool {
  value.request_id == client_request_caller_id(request) &&
  value.epoch.authority_scope_cid == client_request_authority_scope_cid(request)
}
