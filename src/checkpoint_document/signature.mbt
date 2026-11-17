///|
/// Closed Ed25519 Reviewer signature representation. This checks candidate
/// bytes only, never the key, message, caller, authority or cryptographic proof.
/// Decode is bounded by the fixed 88-character canonical Base64 form.
pub fn reviewer_signature_valid(signature : String) -> Bool {
  if signature.length() != 88 || !valid_base64(signature) {
    return false
  }
  let bytes = @base64.decode(signature[:]) catch { _ => return false }
  bytes.length() == 64 && @base64.encode(bytes) == signature
}
