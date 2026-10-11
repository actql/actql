///|
type Library

///|
type Sha256Hasher

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
pub fn load_library(_path : String) -> Result[Library, NativeSignatureIssue] {
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
fn Library::private_cipher(
  _self : Library,
  _key : Bytes,
  _aad : Bytes,
  _input : Bytes,
  _encrypt : Bool,
) -> Result[Bytes, NativePrivateEvidenceIssue] {
  Err(UnsupportedTarget)
}
