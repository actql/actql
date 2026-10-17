///|
pub fn Library::generate_ed25519_key_pair(
  _self : Library,
) -> Result[(Bytes, String), NativeSignatureIssue] {
  Err(UnsupportedTarget)
}
