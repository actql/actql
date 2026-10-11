///|
/// Borrowed immutable originals from the existing capture/Preview/Checkpoint
/// custody Owners. Only that connection can construct this view. It is not a
/// send permit, publication commit, cleanup receipt or authority to disclose.
pub struct ResidentOriginalEffectCompletionEvidence {
  checkpoint_cid : String
  run_definition : @publication.PublicationContract
  invocation : @publication.PublicationContract
  result_definition : @publication.PublicationContract
  result_artifact : @publication.PublicationContract
  result_manifest : @publication.PublicationContract
  computation_receipt : @publication.PublicationContract
  captured : @publication.PublicationContract
  preview : @publication.EffectPreviewIdentity
}

///|
/// Obtain the original completion inputs without Source/Compute replay or
/// copying payload. Current evidence authority and actual original holdings
/// are checked on both sides of the caller callback. The borrowing caller must
/// keep the existing custody alive and revalidate it before publication.
pub fn ResidentEffectReviewRetention::original_completion_evidence(
  self : ResidentEffectReviewRetention,
  consumer : ResidentSourceCompute,
  request : @host.ClientRequestIdentity,
  run_definition : @publication.PublicationContract,
  current : () -> Bool,
  max_bytes : Int,
) -> Result[
  ResidentOriginalEffectCompletionEvidence,
  ResidentEffectReviewRetentionIssue,
] {
  if !current() {
    return Err(EvidenceDenied)
  }
  if max_bytes < 1 || max_bytes > self.limits.max_wire_bytes {
    return Err(InvalidConfiguration)
  }
  match self.confirm_original_checkpoint(consumer, request, run_definition) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let originals = [
    self.materials.run_definition,
    self.invocation,
    self.result.definition,
    self.result.artifact,
    self.result.manifest,
    self.result.receipt,
    self.captured,
  ]
  for original in originals {
    if @utf8.encode(@publication.publication_contract_json(original)).length() >
      max_bytes {
      return Err(ProjectionTooLarge)
    }
  }
  if !current() {
    return Err(EvidenceDenied)
  }
  let persisted = match
    self.confirm_original_checkpoint(consumer, request, run_definition) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    checkpoint_cid: persisted.artifact.checkpoint_cid,
    run_definition: self.materials.run_definition,
    invocation: self.invocation,
    result_definition: self.result.definition,
    result_artifact: self.result.artifact,
    result_manifest: self.result.manifest,
    computation_receipt: self.result.receipt,
    captured: self.captured,
    preview: @strategy.captured_effect_preview_ledger_identity(self.preview),
  })
}
