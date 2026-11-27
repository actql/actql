///|
let private_evidence_version = "actql-private-publication-evidence/0.1"

///|
fn private_evidence_envelope_text(
  nonce : String,
  tag : String,
  ciphertext : String,
) -> String {
  "{\"version\":\"" +
  private_evidence_version +
  "\",\"nonce\":\"" +
  nonce +
  "\",\"tag\":\"" +
  tag +
  "\",\"ciphertext\":\"" +
  ciphertext +
  "\"}"
}

///|
let private_evidence_envelope_fixed : Int = private_evidence_envelope_text(
    "", "", "",
  ).length() +
  16 +
  24

///|
/// Exact plaintext ceiling for one existing physical Store record. The
/// ciphertext expands by whole Base64 groups and keeps the original nonce,
/// tag and framing. The caller still funds all simultaneously held buffers.
pub fn private_evidence_plaintext_limit(record_limit : Int) -> Int {
  if record_limit <= private_evidence_envelope_fixed {
    return 0
  }
  ((record_limit - private_evidence_envelope_fixed) / 4 * 3).min(1048576)
}

///|
/// This protocol preimage binds the role and identity. It issues no authority.
pub fn private_evidence_aad(name : String, cid : String) -> Bytes? {
  if ![
      "effect_preview", "effect_capture", "effect_catalog", "credential_raw_observation",
      "continuation_record", "checkpoint", "model_call_attempt", "model_attempt_accounting",
      "model_attempt_outcome", "model_dispatch_authority", "model_slot_capture",
      "model_invocation_evidence", "model_capture_bundle", "model_attachment_admission",
      "model_raw_response",
    ].contains(name) ||
    cid.length() != 71 ||
    !cid.has_prefix("sha256:") {
    return None
  }
  for ch in cid[7:] {
    if !((ch >= 'a' && ch <= 'f') || (ch >= '0' && ch <= '9')) {
      return None
    }
  }
  Some(
    @utf8.encode(private_evidence_version + "\u0000" + name + "\u0000" + cid),
  )
}

///|
/// Encode the checked extent of the physical nonce, ciphertext and tag.
pub fn encode_private_evidence_envelope(encrypted : Bytes) -> Bytes? {
  let size = encrypted.length()
  guard size > 28 && size <= 1048576 + 28 else { return None }
  let nonce = @base64.encode(encrypted[0:12])
  let tag = @base64.encode(encrypted[size - 16:])
  let ciphertext = @base64.encode(encrypted[12:size - 16])
  Some(@utf8.encode(private_evidence_envelope_text(nonce, tag, ciphertext)))
}

///|
/// Decode the existing private envelope as nonce, ciphertext, then tag.
/// The physical implementation must still authenticate it before any use.
pub fn decode_private_evidence_envelope(envelope : Bytes) -> Bytes? {
  guard envelope.length() <= 1398272 else { return None }
  let wire = @utf8.decode(envelope) catch { _ => return None }
  let value = @moonjson.parse(wire) catch { _ => return None }
  guard value is Object(fields) &&
    fields.length() == 4 &&
    fields.get("version") is Some(String(version)) &&
    version == private_evidence_version &&
    fields.get("nonce") is Some(String(nonce)) &&
    fields.get("tag") is Some(String(tag)) &&
    fields.get("ciphertext") is Some(String(ciphertext)) else {
    return None
  }
  let decode = (text : String) => {
    let bytes = @base64.decode(text) catch { _ => return None }
    if @base64.encode(bytes) != text {
      return None
    }
    Some(bytes)
  }
  guard decode(nonce) is Some(nonce_bytes) &&
    nonce_bytes.length() == 12 &&
    decode(tag) is Some(tag_bytes) &&
    tag_bytes.length() == 16 &&
    decode(ciphertext) is Some(cipher_bytes) &&
    cipher_bytes.length() > 0 &&
    cipher_bytes.length() <= 1048576 else {
    return None
  }
  Some(nonce_bytes + cipher_bytes + tag_bytes)
}
