///|
type Library

///|
type Sha256Hasher

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
