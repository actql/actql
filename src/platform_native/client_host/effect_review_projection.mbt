///|
pub(all) enum NativeClientEffectReviewProjectionIssue {
  Unavailable
  Retention(@resident.ResidentEffectReviewRetentionIssue)
  Journal(NativeClientRunJournalIssue)
}

///|
/// Read the immutable original review under current evidence authority. The
/// journal must still bind this accepted Run to the same saved Checkpoint.
/// Historical evidence access is independent of permission to execute: this
/// method does not claim work, resolve approval, publish or release custody.
pub fn NativeClientEffectSourceWork::review_checkpoint(
  self : NativeClientEffectSourceWork,
  retention : @resident.ResidentEffectReviewRetention,
  authorize_evidence_read : () -> Bool,
  max_bytes : Int,
) -> Result[
  (@checkpoint.SealedCheckpoint, String),
  NativeClientEffectReviewProjectionIssue,
] {
  let current = () => {
    if !authorize_evidence_read() {
      return false
    }
    match self.journal.lookup(self.request, true) {
      Ok(Retained(record)) =>
        record.checkpoint is Some(_) &&
        @publication.publication_contract_identity(record.definition) ==
        @publication.publication_contract_identity(self.definition)
      _ => false
    }
  }
  let (persisted, wire) = match
    retention.original_review_projection(
      self.owner,
      self.request,
      self.definition,
      current,
      max_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Retention(issue))
  }
  match self.journal.lookup(self.request, true) {
    Ok(Retained(record)) if record.checkpoint is Some(checkpoint) &&
      checkpoint.artifact.checkpoint_cid == persisted.artifact.checkpoint_cid &&
      @publication.publication_contract_identity(record.definition) ==
      @publication.publication_contract_identity(self.definition) =>
      Ok((persisted.artifact, wire))
    Ok(_) => Err(Unavailable)
    Err(issue) => Err(Journal(issue))
  }
}
