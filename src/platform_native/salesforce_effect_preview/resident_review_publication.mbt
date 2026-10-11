///|
/// Independently installed Host custody and transport destinations. This
/// configuration is never derived from a poll, proposed Checkpoint or approval.
/// The encryption key stays local; the existing retention Owner pins its first
/// configuration before any Store write and rejects changed retry parameters.
pub(all) struct NativeResidentEffectReviewPublication {
  crypto : @signature.Library
  key : Bytes
  checkpoint_id : String
  created_at : String
  expires_at : String
  limits : @checkpoint.WireLimits
  report_url : String
  artifact_url : String
  access : (Int, @catalog.SingleWriteRequest) -> Result[
    NativeSalesforceTargetAccess,
    NativeSalesforcePreviewIssue,
  ]
}

///|
pub(all) enum NativeResidentEffectReviewPublicationIssue {
  ReadAuthorityDenied
  TargetPreparation(NativeResidentEffectTargetIssue)
  EvidencePersistence(NativeResidentEffectReviewIssue)
  EvidenceUpload(NativeResidentEffectReviewUploadIssue)
}

///|
/// Join the real completed holder to its existing Preview, Store, journal and
/// typed ACK Owners. An explicit retry reuses their original observations and
/// bytes. It never starts Source, Compute or Effect, grants approval, releases
/// task custody, or retries a consumed Provider request. Every failure leaves
/// the Review with its caller, including partially persisted evidence and ACKs.
pub fn NativeResidentEffectReview::publish_review(
  self : NativeResidentEffectReview,
  store : @store.Store,
  client : @http.Client,
  configuration : NativeResidentEffectReviewPublication,
  authorize_evidence_read : () -> Bool,
) -> Result[
  @remote.RemoteEffectCheckpointReport,
  NativeResidentEffectReviewPublicationIssue,
] {
  if !authorize_evidence_read() {
    return Err(ReadAuthorityDenied)
  }
  match self.observe(configuration.access) {
    Ok(_) => ()
    Err(issue) => return Err(TargetPreparation(issue))
  }
  // Provider I/O may have outlived disclosure authority. Keep its exact use
  // and outcome, but do not construct or publish a review under stale authority.
  if !authorize_evidence_read() {
    return Err(ReadAuthorityDenied)
  }
  let report = match
    self.persist_and_retain_report(
      store,
      configuration.crypto,
      configuration.key,
      configuration.checkpoint_id,
      configuration.created_at,
      configuration.expires_at,
      configuration.limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(EvidencePersistence(issue))
  }
  if !authorize_evidence_read() {
    return Err(ReadAuthorityDenied)
  }
  match
    self.upload_review_projection(
      client,
      configuration.report_url,
      configuration.artifact_url,
      authorize_evidence_read,
    ) {
    Ok(_) => Ok(report)
    Err(issue) => Err(EvidenceUpload(issue))
  }
}
