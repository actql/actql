///|
/// The authority's authenticated validity interval is separate from a Run's
/// immutable execution definition. This handle is identity, not permission.
struct SubmissionEpoch {
  authority_scope_cid : String
  epoch_nonce : String
  not_before : Double
  expires_at : Double
  wire : String
  cid : String
} derive(Eq, Debug)

///|
pub(all) enum SubmissionIdentityIssue {
  InvalidAuthority
  InvalidEpochNonce
  InvalidInterval
  InvalidClock
  InvalidSubmissionNonce
  Encoding
} derive(Eq, Debug)

///|
pub(all) enum SubmissionEpochValidity {
  Admissible
  NotYetValid
  Expired
} derive(Eq, Debug)

///|
fn valid_submission_milliseconds(value : Double) -> Bool {
  !value.is_nan() &&
  !value.is_inf() &&
  value >= 0.0 &&
  value <= 9007199254740991.0 &&
  value.trunc() == value &&
  !(value == 0.0 && 1.0 / value < 0.0)
}

///|
/// Authentication and durable validation-material custody are Host facts.
/// Admission below checks the exact authenticated body without normalization.
pub fn prepare_submission_epoch(
  authority_scope_cid : String,
  epoch_nonce : String,
  not_before : Double,
  expires_at : Double,
) -> Result[SubmissionEpoch, SubmissionIdentityIssue] {
  if !valid_scope_cid(authority_scope_cid) {
    return Err(InvalidAuthority)
  }
  if !valid_scope_cid("sha256:" + epoch_nonce) {
    return Err(InvalidEpochNonce)
  }
  if !valid_submission_milliseconds(not_before) ||
    !valid_submission_milliseconds(expires_at) ||
    expires_at <= not_before {
    return Err(InvalidInterval)
  }
  let writer = @encode.writer(2048, 8, 1) catch { _ => return Err(Encoding) }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "authority_scope_cid")
    @encode.string_value(writer, authority_scope_cid)
    @encode.key(writer, "epoch_nonce")
    @encode.string_value(writer, epoch_nonce)
    @encode.key(writer, "expires_at")
    @encode.number_value(writer, expires_at)
    @encode.key(writer, "not_before")
    @encode.number_value(writer, not_before)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-submission-epoch/0.1")
    @encode.end_object(writer)
    let wire = @encode.finish(writer)
    Ok({
      authority_scope_cid,
      epoch_nonce,
      not_before,
      expires_at,
      wire,
      cid: "sha256:" + @sha.hex(@utf8.encode(wire)),
    })
  } catch {
    _ => Err(Encoding)
  }
}

///|
pub fn submission_epoch_wire(epoch : SubmissionEpoch) -> String {
  epoch.wire
}

///|
pub fn submission_epoch_cid(epoch : SubmissionEpoch) -> String {
  epoch.cid
}

///|
pub fn submission_epoch_validity(
  epoch : SubmissionEpoch,
  now : Double,
) -> Result[SubmissionEpochValidity, SubmissionIdentityIssue] {
  if !valid_submission_milliseconds(now) {
    return Err(InvalidClock)
  }
  if now < epoch.not_before {
    Ok(NotYetValid)
  } else if now >= epoch.expires_at {
    Ok(Expired)
  } else {
    Ok(Admissible)
  }
}

///|
/// An authority-issued epoch plus a caller-allocated nonce identifies an
/// intent before checking or Run issuance. Existing Run/Effect logical keys
/// may use this CID as their caller ID; their published preimages do not change.
pub fn submission_request_id(
  epoch : SubmissionEpoch,
  caller_nonce : String,
) -> Result[String, SubmissionIdentityIssue] {
  if !valid_caller_id(caller_nonce, 256) {
    return Err(InvalidSubmissionNonce)
  }
  let writer = @encode.hashing_writer(2048, 4, 1) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "caller_nonce")
    @encode.string_value(writer, caller_nonce)
    @encode.key(writer, "epoch_cid")
    @encode.string_value(writer, epoch.cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-submission-identity/0.1")
    @encode.end_object(writer)
    Ok("sha256:" + @encode.finish_hash(writer))
  } catch {
    _ => Err(Encoding)
  }
}
