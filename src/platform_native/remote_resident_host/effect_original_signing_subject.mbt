///|
/// Internal metadata projection from the same opaque approval/capture custody.
/// It returns original invocation/unit identities only, never a permission,
/// replacement capture, use claim or durable restart witness.
pub fn ResidentOriginalEffectApprovalScope::original_signing_subject_for(
  self : ResidentOriginalEffectApprovalScope,
  request : @host.ClientRequestIdentity,
  run_definition_cid : String,
  checkpoint_cid : String,
) -> Result[(String, String), ResidentEffectReviewRetentionIssue] {
  guard self.current_for(request, run_definition_cid, checkpoint_cid)
    is Some(authority) else {
    return Err(Unavailable)
  }
  let owner = self.retention
  guard owner.capture_owner is Some(capture) &&
    capture.original is Some(funded) &&
    funded.evidence is Some(original) &&
    !capture.released &&
    !funded.physical_cleanup_confirmed &&
    @resources.capacity_reservation_open(funded.reservation) else {
    return Err(Unavailable)
  }
  // Retained evidence is issued only by the existing complete computation
  // chain Owner. Equal incoming/caller CIDs cannot construct this original.
  let invocation = original.invocation
  if @publication.publication_contract_json(original.run) !=
    @publication.publication_contract_json(owner.materials.run_definition) ||
    @publication.publication_contract_json(invocation) !=
    @publication.publication_contract_json(owner.invocation) {
    return Err(Unavailable)
  }
  let unit = match @host.client_effect_review_checkpoint_unit_definition_cid(
    owner.materials.allowed,
    owner.materials.run_definition,
    self.checkpoint.artifact,
  ) {
    Ok(value) => value
    Err(_) => return Err(Unavailable)
  }
  if self.current_for(request, run_definition_cid, checkpoint_cid) !=
    Some(authority) {
    return Err(Unavailable)
  }
  // Current callbacks may retire holdings; never return a projection after
  // that lifetime ends, replace it with fresh facts or renew its reservation.
  guard capture.original is Some(after) &&
    physical_equal(after, funded) &&
    after.evidence is Some(evidence) &&
    !capture.released &&
    !after.physical_cleanup_confirmed &&
    @resources.capacity_reservation_open(after.reservation) &&
    @publication.publication_contract_json(evidence.invocation) ==
    @publication.publication_contract_json(invocation) &&
    @publication.publication_contract_json(evidence.run) ==
    @publication.publication_contract_json(owner.materials.run_definition) else {
    return Err(Unavailable)
  }
  Ok((@publication.publication_contract_identity(invocation), unit))
}
