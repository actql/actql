///|
type Library

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
