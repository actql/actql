///|
type OriginalKeySigningAttempt

///|
pub fn OriginalKeySigningAttempt::require_original_owner(
  _self : OriginalKeySigningAttempt,
) -> Result[Unit, NativeSignatureIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Library::prepare_original_key_signing_attempt(
  _self : Library,
  _key : @filesystem.PrivateFileProjection,
  _expected_public_key : Bytes,
  _preimage : Bytes,
) -> Result[OriginalKeySigningAttempt, NativeSignatureIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn OriginalKeySigningAttempt::sign_once(
  _self : OriginalKeySigningAttempt,
) -> Result[String, NativeSignatureIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn OriginalKeySigningAttempt::original_signature(
  _self : OriginalKeySigningAttempt,
) -> Result[String, NativeSignatureIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn OriginalKeySigningAttempt::primary_issue(
  _self : OriginalKeySigningAttempt,
) -> NativeSignatureIssue? {
  Some(UnsupportedTarget)
}

///|
pub fn OriginalKeySigningAttempt::close_checked(
  _self : OriginalKeySigningAttempt,
) -> Result[Unit, NativeSignatureIssue] {
  Err(UnsupportedTarget)
}
