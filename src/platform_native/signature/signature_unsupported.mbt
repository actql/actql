///|
type Library

///|
type Sha256Hasher

///|
pub fn Library::require_current(
  _self : Library,
) -> Result[Unit, NativeSignatureIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Library::close_checked(
  _self : Library,
) -> Result[Unit, NativeSignatureIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Sha256Hasher::close_checked(
  _self : Sha256Hasher,
) -> Result[Unit, NativeSignatureIssue] {
  Err(UnsupportedTarget)
}

///|
/// No installed Native Library fact exists on unsupported targets.
pub fn Library::diagnostic_ceiling(_self : Library) -> Int? {
  None
}

///|
pub fn Library::random_bytes(
  _self : Library,
  _length : Int,
) -> Result[Bytes, NativeSignatureIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Library::hmac_sha256(
  _self : Library,
  _key : Bytes,
  _message : Bytes,
) -> Result[Bytes, NativeSignatureIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Library::verify_hmac_sha256(
  _self : Library,
  _key : Bytes,
  _message : Bytes,
  _tag : Bytes,
) -> Result[Bool, NativeSignatureIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Library::sha256_hasher(
  _self : Library,
) -> Result[Sha256Hasher, NativeSignatureIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Sha256Hasher::update(
  _self : Sha256Hasher,
  _bytes : Bytes,
) -> Result[Unit, NativeSignatureIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Sha256Hasher::finish_hex(
  _self : Sha256Hasher,
) -> Result[String, NativeSignatureIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn load_library(
  _path : String,
  diagnostic_ceiling? : Int? = None,
) -> Result[Library, NativeSignatureIssue] {
  if diagnostic_ceiling is Some(value) && value <= 0 {
    return Err(InvalidInput)
  }
  ignore(@utf8.encode(""))
  Err(UnsupportedTarget)
}

///|
pub fn Library::verify_ed25519(
  _self : Library,
  _public_key_pem : String,
  _message : Bytes,
  _signature_base64url : String,
) -> Result[Bool, NativeSignatureIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Library::sign_ed25519(
  _self : Library,
  _private_key_pem : Bytes,
  _message : Bytes,
) -> Result[String, NativeSignatureIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Library::ed25519_public_key_raw32(
  _self : Library,
  _public_key_pem : String,
) -> Result[Bytes, NativeSignatureIssue] {
  Err(UnsupportedTarget)
}

///|
fn Library::private_cipher(
  _self : Library,
  _key : Bytes,
  _aad : Bytes,
  _input : Bytes,
  _encrypt : Bool,
) -> Result[Bytes, NativePrivateEvidenceIssue] {
  Err(UnsupportedTarget)
}
