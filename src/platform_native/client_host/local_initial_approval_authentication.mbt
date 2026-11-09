///|
// The Common Owner has already admitted the exact Evidence/Checkpoint/claims.
// Verify its separate Reviewer proof with the SAME authenticated key before
// issuing any Host attestation preparation. No caller Allow or fresh key exists.
fn NativeLocalAuthenticatedEffectReviewer::require_approval_signature_locked(
  self : NativeLocalAuthenticatedEffectReviewer,
  admitted : @checkpoint.AdmittedResolution,
) -> Result[Unit, NativeClientRunJournalIssue] {
  let host = self.binding.host
  if !host.journal.transaction_active || host.journal.fenced {
    return Err(Fenced)
  }
  let proof = match admitted.approval_proof_materials(self.limits) {
    Ok(None) => return Ok(())
    Ok(Some(value)) => value
    Err(issue) => return Err(Checkpoint(Signature(Resolution(issue))))
  }
  let (key_id, preimage, signature) = proof
  if key_id != self.registration.key_id || signature.length() != 88 {
    return Err(Checkpoint(Signature(AttestationRejected)))
  }
  let bytes = @base64.decode(signature[:]) catch {
    _ => return Err(Checkpoint(Signature(AttestationRejected)))
  }
  if bytes.length() != 64 || @base64.encode(bytes) != signature {
    return Err(Checkpoint(Signature(AttestationRejected)))
  }
  let transport = @base64.encode(bytes, padding=false)
    .replace_all(old="+", new="-")
    .replace_all(old="/", new="_")
  match
    host.epoch.crypto.verify_ed25519(
      self.registration.public_key_pem,
      @utf8.encode(preimage),
      transport,
    ) {
    Ok(true) => Ok(())
    Ok(false) => Err(Checkpoint(Signature(AttestationRejected)))
    Err(issue) => Err(Checkpoint(Signature(Signature(issue))))
  }
}
