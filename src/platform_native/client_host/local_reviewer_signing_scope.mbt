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
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match self.key.require_reviewer_signing_key_scope(scope) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match self.require_original_reviewer_signing_subject(scope) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // The subject reader's last clock/RunRead callback may replace the original
  // key file. Export compares that same Root/file generation without invoking
  // another caller callback; it cannot retire the already-fenced capture.
  // This is original projection custody, not private/public-key correspondence.
  match self.key.projection.export_original() {
    Ok(original) if original == self.key.exported => Ok(())
    Ok(_) | Err(_) => Err(ProofKey(SigningOriginalUnavailable))
  }
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
  let (request, logical_scope, invocation, unit) = match
    self.original_signing_subject() {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let submission = match self.original_signing_submission_scope() {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let key = self.key
  let account = key.account
  let (_, _, principal, _, _, key_id, _, _) = @credential_resource.native_local_signing_key_selection_projection(
    account.selection,
  )
  let checkpoint = self.original.artifact
  let scope : @credential.LocalSigningCredentialScope = {
    account_configuration_cid: account.account_configuration_cid,
    account_id: account.account_id,
    attempt_id,
    authority_scope_cid: account.scope,
    checkpoint_cid: checkpoint.checkpoint_cid,
    checkpoint_id: checkpoint.checkpoint.checkpoint_id,
    checkpoint_kind: checkpoint.checkpoint.kind,
    host_adoption_cid: account.host.adoption_cid,
    key_configuration_cid: account.file.content_cid,
    key_generation_cid: key.generation_cid,
    key_id,
    key_public_key_cid: key.public_key.cid(),
    preimage: self.proof.preimage(),
    principal,
    request_cid: request,
    request_scope_cid: logical_scope,
    run_definition_cid: self.reviewer.original.run_definition_cid,
    run_invocation_cid: invocation,
    submission_scope_cid: submission,
    unit_definition_cid: unit,
    purpose: @credential.ReviewerProof,
  }
  // The Submission lookup and key/Account reads above may run current/clock
  // callbacks. Re-read original correspondence and finish with the existing
  // noncallback paired-capture lifetime fence, including on mismatch paths.
  self.require_original_signing_scope(scope).map(_ => scope)
}
