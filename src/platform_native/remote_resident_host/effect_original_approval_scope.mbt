///|
/// Issued only by the original paired custody Owner. This is neither an
/// approval nor a permission to disclose the retained review or resume it.
struct ResidentOriginalEffectApprovalScope {
  retention : ResidentEffectReviewRetention
  checkpoint : @checkpoint.PersistedCheckpoint
}

///|
fn original_effect_preview_authority_matches(
  preview : @publication.EffectPreviewIdentity,
  authority : String,
) -> Bool {
  let members = @publication.effect_preview_member_count(preview)
  if members != 1 {
    return false
  }
  for index in 0..<members {
    if @publication.effect_preview_member_authority_scope_cid(preview, index) !=
      Some(authority) {
      return false
    }
  }
  true
}

///|
/// Project the scope only after authenticating the original computation,
/// Preview and persisted Checkpoint. No incoming Resolution supplies it.
pub fn ResidentEffectReviewRetention::original_approval_scope(
  self : ResidentEffectReviewRetention,
) -> Result[
  ResidentOriginalEffectApprovalScope,
  ResidentEffectReviewRetentionIssue,
] {
  let checkpoint = match
    self.confirm_original_checkpoint(
      self.consumer,
      self.request,
      self.materials.run_definition,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let value : ResidentOriginalEffectApprovalScope = {
    retention: self,
    checkpoint,
  }
  match
    value.current_for(
      self.request,
      @publication.publication_contract_identity(self.materials.run_definition),
      checkpoint.artifact.checkpoint_cid,
    ) {
    Some(_) => Ok(value)
    None => Err(Unavailable)
  }
}

///|
/// Reauthenticate the same owners at use. The original issuer checked the
/// Preview keys against this exact logical request scope and encoded the
/// request authority scope into the Checkpoint's immutable continuation.
/// A replaced Checkpoint, released holding or different request is refused.
pub fn ResidentOriginalEffectApprovalScope::current_for(
  self : ResidentOriginalEffectApprovalScope,
  request : @host.ClientRequestIdentity,
  run_definition_cid : String,
  checkpoint_cid : String,
) -> String? {
  let owner = self.retention
  if owner.request != request ||
    @publication.publication_contract_identity(owner.materials.run_definition) !=
    run_definition_cid ||
    self.checkpoint.artifact.checkpoint_cid != checkpoint_cid {
    return None
  }
  let actual = match
    owner.confirm_original_checkpoint(
      owner.consumer,
      request,
      owner.materials.run_definition,
    ) {
    Ok(value) => value
    Err(_) => return None
  }
  guard actual == self.checkpoint &&
    owner.review is Some(review) &&
    review.checkpoint == actual.artifact &&
    actual.artifact.checkpoint.kind == @checkpoint.EffectSet &&
    actual.artifact.checkpoint.continuation_state_cid ==
    "sha256:" + @sha.hex(@utf8.encode(review.continuation_wire)) &&
    owner.preview_owner is Some(preview) else {
    return None
  }
  let (identity, _) = match preview.confirm() {
    Ok(value) => value
    Err(_) => return None
  }
  let scope = match
    @host.prepared_client_effect_request_scope(
      owner.materials.prepared,
      request,
    ) {
    Ok(value) => value
    Err(_) => return None
  }
  let authority = @effect.logical_request_scope_authority(scope)
  if authority != @host.client_request_authority_scope_cid(request) {
    return None
  }
  // Dispatch-key scope alone does not prove the member's approval scope.
  // Read the actual admitted Preview field; a different or absent member
  // scope cannot be replaced by the Client scope or incoming Resolution.
  if !original_effect_preview_authority_matches(identity, authority) {
    return None
  }
  if @effect.recover_effect_preview_apply_keys(
      identity, scope, 1, 10000, 20000, 4096, 32, 8,
    )
    is Err(_) {
    return None
  }
  // Confirmation also follows the Preview read. No lifetime or reservation
  // is renewed; failure leaves the original custody and cleanup responsibility.
  match
    owner.confirm_original_checkpoint(
      owner.consumer,
      request,
      owner.materials.run_definition,
    ) {
    Ok(value) if value == actual => Some(authority)
    _ => None
  }
}
