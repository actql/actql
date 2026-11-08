///|
pub(all) enum NativePrivateEvidenceIssue {
  UnsupportedTarget
  InvalidInput
  CipherRejected
} derive(Eq, Debug)

///|
fn private_evidence_binding(name : String, cid : String) -> Bytes? {
  if ![
      "effect_preview", "effect_capture", "effect_catalog", "credential_raw_observation",
      "continuation_record", "checkpoint", "model_call_attempt", "model_attempt_accounting",
      "model_attempt_outcome", "model_dispatch_authority", "model_slot_capture",
      "model_invocation_evidence", "model_capture_bundle", "model_attachment_admission",
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
    @utf8.encode(
      "actql-private-publication-evidence/0.1\u0000" + name + "\u0000" + cid,
    ),
  )
}

///|
/// Physical encryption only. Semantic issuance, current authority and durable
/// holding confirmation remain with the existing publication/Store Owners.
/// The envelope and authenticated preimage match the existing Node Store.
pub fn Library::seal_private_evidence(
  self : Library,
  key : Bytes,
  name : String,
  semantic_cid : String,
  plaintext : Bytes,
) -> Result[Bytes, NativePrivateEvidenceIssue] {
  guard key.length() == 32 &&
    plaintext.length() > 0 &&
    plaintext.length() <= 1048576 &&
    private_evidence_binding(name, semantic_cid) is Some(aad) else {
    return Err(InvalidInput)
  }
  let encrypted = match self.private_cipher(key, aad, plaintext, true) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let nonce = @base64.encode(encrypted[0:12])
  let tag = @base64.encode(encrypted[encrypted.length() - 16:])
  let ciphertext = @base64.encode(encrypted[12:encrypted.length() - 16])
  Ok(
    @utf8.encode(
      "{\"version\":\"actql-private-publication-evidence/0.1\",\"nonce\":\"" +
      nonce +
      "\",\"tag\":\"" +
      tag +
      "\",\"ciphertext\":\"" +
      ciphertext +
      "\"}",
    ),
  )
}

///|
/// Authentication succeeds before plaintext enters the managed heap. Wrong
/// key, semantic identity, evidence role or modified bytes are never repaired.
pub fn Library::open_private_evidence(
  self : Library,
  key : Bytes,
  name : String,
  semantic_cid : String,
  envelope : Bytes,
) -> Result[Bytes, NativePrivateEvidenceIssue] {
  guard key.length() == 32 &&
    envelope.length() <= 1398272 &&
    private_evidence_binding(name, semantic_cid) is Some(aad) else {
    return Err(InvalidInput)
  }
  let wire = @utf8.decode(envelope) catch { _ => return Err(InvalidInput) }
  let value = @json.parse(wire) catch { _ => return Err(InvalidInput) }
  guard value is Object(fields) &&
    fields.length() == 4 &&
    fields.get("version")
    is Some(String("actql-private-publication-evidence/0.1")) &&
    fields.get("nonce") is Some(String(nonce)) &&
    fields.get("tag") is Some(String(tag)) &&
    fields.get("ciphertext") is Some(String(ciphertext)) else {
    return Err(InvalidInput)
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
    return Err(InvalidInput)
  }
  self.private_cipher(key, aad, nonce_bytes + cipher_bytes + tag_bytes, false)
}
