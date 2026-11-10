///|
// Key correspondence is independent of the original Client, Submission and
// paired-capture subject. This does not accept an issuer or acquire a use.
fn NativeLocalSigningKeyOriginal::require_reviewer_signing_key_scope(
  self : NativeLocalSigningKeyOriginal,
  scope : @credential.LocalSigningCredentialScope,
) -> Result[Unit, NativeLocalReviewerProofMaterialsIssue] {
  match self.require_current_key() {
    Err(issue) => return Err(ProofKey(issue))
    Ok(_) => ()
  }
  let account = self.account
  let (_, purpose, principal, _, _, key_id, _, _) = @credential_resource.native_local_signing_key_selection_projection(
    account.selection,
  )
  if purpose != @credential.ReviewerProof ||
    scope.purpose != purpose ||
    scope.account_configuration_cid != account.account_configuration_cid ||
    scope.account_id != account.account_id ||
    scope.authority_scope_cid != account.scope ||
    scope.host_adoption_cid != account.host.adoption_cid ||
    scope.key_configuration_cid != account.file.content_cid ||
    scope.key_generation_cid != self.generation_cid ||
    scope.key_id != key_id ||
    scope.key_public_key_cid != self.public_key.cid() ||
    scope.principal != principal ||
    scope.checkpoint_kind != account.kind {
    return Err(ProofUnavailable)
  }
  Ok(())
}

///|
/// Compare candidate metadata to this same original key, Client Submission and
/// paired Checkpoint subject. The terminal noncallback capture fence remains
/// after all current callbacks. Success is not issuer authority, grant custody,
/// a signing permit, a durable use claim or private/public-key correspondence.
pub fn NativeLocalReviewerProofMaterials::require_original_signing_scope(
  self : NativeLocalReviewerProofMaterials,
  scope : @credential.LocalSigningCredentialScope,
) -> Result[Unit, NativeLocalReviewerProofMaterialsIssue] {
  self.read_original_signing_scope(scope).map(_ => ())
}

///|
// Keep the actual checked subject instead of discarding it at the Unit facade.
// This private view lasts only through the existing signing operation; every
// later transaction/physical-signing boundary performs its own current checks.
fn NativeLocalReviewerProofMaterials::read_original_signing_scope(
  self : NativeLocalReviewerProofMaterials,
  scope : @credential.LocalSigningCredentialScope,
) -> Result[
  NativeLocalOriginalEffectSigningSubjectRead,
  NativeLocalReviewerProofMaterialsIssue,
] {
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match self.key.require_signing_key_scope(scope) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let subject = match
    self.read_original_reviewer_signing_subject_after_current(scope) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // The subject reader's last clock/RunRead callback may replace the original
  // key file. Export compares that same Root/file generation without invoking
  // another caller callback; it cannot retire the already-fenced capture.
  // This is original projection custody, not private/public-key correspondence.
  self.key.finish_original_projection().map(_ => subject)
}

///|
/// Prepare metadata from the opaque original key/Checkpoint/capture and the
/// authenticated retained Submission. Only the explicitly chosen attempt name
/// is caller input; no caller CID, replacement compilation or fresh capture is
/// used. Issuer authority, finite grant limits, durable adoption/use/outcome
/// and current physical signing must pass their independent existing Owners.
pub fn NativeLocalReviewerProofMaterials::prepare_signing_scope(
  self : NativeLocalReviewerProofMaterials,
  attempt_id : String,
) -> Result[
  @credential.LocalSigningCredentialScope,
  NativeLocalReviewerProofMaterialsIssue,
] {
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Same existing Credential attempt syntax, without issuing a dummy grant to
  // validate it. A changed attempt is never an internal retry or a use claim.
  if attempt_id.is_empty() ||
    attempt_id.length() > 256 ||
    attempt_id.contains("\u{0}") {
    return Err(ProofUnavailable)
  }
  let subject = match self.read_original_signing_subject_after_current() {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let (invocation, unit) = match subject.original_subject_after_current() {
    Err(_) => return Err(ProofUnavailable)
    Ok(value) => value
  }
  let submission = match
    self.original_signing_submission_scope_after_current() {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let request = @host.client_request_intent_cid(self.reviewer.request)
  let logical_scope = @host.client_request_scope_cid(self.reviewer.request)
  let key = self.key.scope_fields()
  let checkpoint = self.original.artifact
  let scope : @credential.LocalSigningCredentialScope = {
    account_configuration_cid: key.account_configuration_cid,
    account_id: key.account_id,
    attempt_id,
    authority_scope_cid: key.authority_scope_cid,
    checkpoint_cid: checkpoint.checkpoint_cid,
    checkpoint_id: checkpoint.checkpoint.checkpoint_id,
    checkpoint_kind: checkpoint.checkpoint.kind,
    host_adoption_cid: key.host_adoption_cid,
    key_configuration_cid: key.key_configuration_cid,
    key_generation_cid: key.key_generation_cid,
    key_id: key.key_id,
    key_public_key_cid: key.key_public_key_cid,
    preimage: self.proof.preimage(),
    principal: key.principal,
    request_cid: request,
    request_scope_cid: logical_scope,
    run_definition_cid: self.reviewer.original.run_definition_cid,
    run_invocation_cid: invocation,
    submission_scope_cid: submission,
    unit_definition_cid: unit,
    purpose: @credential.ReviewerProof,
  }
  // Every field was derived from these SAME current originals; there is no
  // candidate scope to re-admit. Submission already ran the complete material
  // fence after its callback. Keep the final original key and subject fences
  // rather than discard their observations and traverse the whole scope again.
  match self.key.finish_original_projection() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match subject.original_subject_after_current() {
    Ok((after_invocation, after_unit)) if after_invocation == invocation &&
      after_unit == unit => Ok(scope)
    Ok(_) | Err(_) => Err(ProofUnavailable)
  }
}
