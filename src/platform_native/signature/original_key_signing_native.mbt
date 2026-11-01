///|
/// One physical attempt under the same Library and private-file original. This
/// is not a Credential use or approval. The Host must durably confirm its exact
/// original signing use and current subject before calling sign_once.
type OriginalKeySigningAttempt

///|
#borrow(original)
extern "C" fn original_key_signing_owner_current_ffi(
  original : OriginalKeySigningAttempt,
) -> Bool = "actql_native_original_key_signing_owner_current"

///|
/// Noncallback process/thread and original-child lifetime observation only.
/// A Host uses this before spending its local phase, then checks all actual
/// subject/key/current authority independently. Success grants no signing use,
/// new attempt, descriptor acquisition or cleanup acknowledgement.
pub fn OriginalKeySigningAttempt::require_original_owner(
  self : OriginalKeySigningAttempt,
) -> Result[Unit, NativeSignatureIssue] {
  if original_key_signing_owner_current_ffi(self) {
    Ok(())
  } else {
    Err(Signing("original signing owner unavailable"))
  }
}

///|
#borrow(library, key, expected_public_key, preimage)
extern "C" fn original_key_signing_prepare_ffi(
  library : Library,
  key : @filesystem.PrivateFileProjection,
  expected_public_key : Bytes,
  public_length : Int,
  preimage : Bytes,
  preimage_length : Int,
) -> OriginalKeySigningAttempt = "actql_native_original_key_signing_prepare"

///|
#borrow(original)
extern "C" fn original_key_signing_ready_ffi(
  original : OriginalKeySigningAttempt,
) -> Bool = "actql_native_original_key_signing_ready"

///|
#borrow(original)
extern "C" fn original_key_signing_once_ffi(
  original : OriginalKeySigningAttempt,
) -> Int = "actql_native_original_key_signing_once"

///|
#borrow(original)
extern "C" fn original_key_signing_primary_ffi(
  original : OriginalKeySigningAttempt,
) -> Int = "actql_native_original_key_signing_primary"

///|
#borrow(original)
extern "C" fn original_key_signing_close_ffi(
  original : OriginalKeySigningAttempt,
) -> Int = "actql_native_original_key_signing_close"

///|
#borrow(original, output)
extern "C" fn original_key_signing_copy_ffi(
  original : OriginalKeySigningAttempt,
  output : Bytes,
  length : Int,
) -> Bool = "actql_native_original_key_signing_copy"

///|
fn original_key_signing_issue(status : Int) -> NativeSignatureIssue {
  match status {
    2 => InvalidInput
    3 => InvalidPrivateKey("private key decode rejected")
    4 => UnsupportedKey("private key is not Ed25519")
    6 => Signing("original private file changed or unavailable")
    7 => InvalidPrivateKey("original private and public keys do not match")
    8 => Signing("original signing attempt already spent")
    9 => CleanupPending
    10 => Signing("original signing attempt unavailable")
    _ => Signing("physical signing result unavailable")
  }
}

///|
/// Retain existing originals and bounded immutable public/preimage DATA only.
/// No private file is opened and no signature or credential ordinal is issued.
pub fn Library::prepare_original_key_signing_attempt(
  self : Library,
  key : @filesystem.PrivateFileProjection,
  expected_public_key : Bytes,
  preimage : Bytes,
) -> Result[OriginalKeySigningAttempt, NativeSignatureIssue] {
  if expected_public_key.length() != 32 || preimage.length() > 1048576 {
    return Err(InvalidInput)
  }
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let original = original_key_signing_prepare_ffi(
    self,
    key,
    expected_public_key,
    expected_public_key.length(),
    preimage,
    preimage.length(),
  )
  if original_key_signing_ready_ffi(original) {
    Ok(original)
  } else {
    let issue = original.primary_issue().unwrap_or(InvalidInput)
    // Refused construction has acquired no descriptor or private material.
    let _ = original.close_checked()
    Err(issue)
  }
}

///|
/// Spend before physical key work. Check the retained generation before/after
/// reading and signing; verify its actual public key before signing. No private
/// bytes escape. Failure never permits another attempt or acknowledges cleanup.
pub fn OriginalKeySigningAttempt::sign_once(
  self : OriginalKeySigningAttempt,
) -> Result[String, NativeSignatureIssue] {
  match original_key_signing_once_ffi(self) {
    0 => self.original_signature()
    code => Err(original_key_signing_issue(code))
  }
}

///|
/// Copy only this same completed signature after descriptor-close ACK. This
/// issues no new signature, Allow or use, and performs no private-file read.
/// The Host still checks current authority before returning or storing it.
pub fn OriginalKeySigningAttempt::original_signature(
  self : OriginalKeySigningAttempt,
) -> Result[String, NativeSignatureIssue] {
  let output = Bytes::make(64, 0)
  if !original_key_signing_copy_ffi(self, output, output.length()) {
    return Err(Signing("original signature unavailable"))
  }
  Ok(
    @base64.encode(output)
    .replace_all(old="+", new="-")
    .replace_all(old="/", new="_")
    .replace_all(old="=", new=""),
  )
}

///|
/// Primary attempt failure is separate from pending descriptor retirement.
/// None is not a cleanup ACK or proof that signing was never attempted.
pub fn OriginalKeySigningAttempt::primary_issue(
  self : OriginalKeySigningAttempt,
) -> NativeSignatureIssue? {
  match original_key_signing_primary_ffi(self) {
    -1 | 0 => None
    code => Some(original_key_signing_issue(code))
  }
}

///|
/// Child-first cleanup in the original process/thread. An uncertain close
/// stays pending and is never reclosed; the same receiver must be retained.
/// Library module ACK and Host/Credential outcome duties remain separate.
pub fn OriginalKeySigningAttempt::close_checked(
  self : OriginalKeySigningAttempt,
) -> Result[Unit, NativeSignatureIssue] {
  match original_key_signing_close_ffi(self) {
    0 => Ok(())
    1 => Err(CleanupPending)
    _ => Err(InvalidInput)
  }
}
