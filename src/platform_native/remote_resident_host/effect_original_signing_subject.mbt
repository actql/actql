///|
// A bounded read view in the existing approval/capture Owner. These exact
// references have no cleanup authority and cannot keep retired backing open.
// Caller control holding for this record remains independently required.
struct ResidentOriginalEffectSigningSubjectRead {
  scope : ResidentOriginalEffectApprovalScope
  capture : ResidentEffectCaptureCustody
  funded : FundedResidentEffectComputation
  evidence : OriginalResidentEffectComputationEvidence
  unit_definition_cid : String
}

///|
/// Recheck the original reference lifetime after every caller current callback.
/// This reads existing Owner fields only: no Store read, clock, authorization,
/// current_for callback, replacement evidence or renewed reservation occurs.
pub fn ResidentOriginalEffectSigningSubjectRead::original_subject_after_current(
  self : ResidentOriginalEffectSigningSubjectRead,
) -> Result[(String, String), ResidentEffectReviewRetentionIssue] {
  let owner = self.scope.retention
  guard !owner.retiring &&
    !owner.retired &&
    owner.capture_owner is Some(capture) &&
    physical_equal(capture, self.capture) &&
    !capture.released &&
    capture.original is Some(funded) &&
    physical_equal(funded, self.funded) &&
    !funded.physical_cleanup_confirmed &&
    @resources.capacity_reservation_open(funded.reservation) &&
    funded.evidence is Some(evidence) &&
    physical_equal(evidence, self.evidence) else {
    return Err(Unavailable)
  }
  Ok(
    (
      @publication.publication_contract_identity(self.evidence.invocation),
      self.unit_definition_cid,
    ),
  )
}

///|
/// Retain only the same original read references across caller current checks.
/// This issues no permission, replacement capture or cleanup/use capability.
pub fn ResidentOriginalEffectApprovalScope::read_original_signing_subject_for(
  self : ResidentOriginalEffectApprovalScope,
  request : @host.ClientRequestIdentity,
  run_definition_cid : String,
  checkpoint_cid : String,
) -> Result[
  ResidentOriginalEffectSigningSubjectRead,
  ResidentEffectReviewRetentionIssue,
] {
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
  let unit = match
    @host.client_effect_review_checkpoint_unit_definition_cid(
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
  let read : ResidentOriginalEffectSigningSubjectRead = {
    scope: self,
    capture,
    funded,
    evidence: original,
    unit_definition_cid: unit,
  }
  read.original_subject_after_current().map(_ => read)
}

///|
/// Compatible immediate metadata projection. Callers which execute their own
/// current callbacks afterwards must retain the read view and use its terminal
/// noncallback lifetime check after those callbacks instead.
pub fn ResidentOriginalEffectApprovalScope::original_signing_subject_for(
  self : ResidentOriginalEffectApprovalScope,
  request : @host.ClientRequestIdentity,
  run_definition_cid : String,
  checkpoint_cid : String,
) -> Result[(String, String), ResidentEffectReviewRetentionIssue] {
  self
  .read_original_signing_subject_for(
    request, run_definition_cid, checkpoint_cid,
  )
  .bind(read => read.original_subject_after_current())
}
