///|
pub(all) enum NativeClientEffectReviewWaitingIssue {
  Original(NativeClientSourceWorkIssue)
  Retention(@resident.ResidentEffectReviewRetentionIssue)
  Journal(NativeClientRunJournalIssue)
}

///|
/// Commit waiting to the accepted original Run using authenticated capture,
/// Preview and Checkpoint custody. The existing journal validates the checked
/// Effect owner, revision, cancellation fence and supplied original Host
/// binding. Neither a Remote report nor a caller-authored receipt can replace
/// those Owners. This does not approve or send an Effect or release its input.
pub fn NativeClientEffectSourceWork::wait_review_checkpoint(
  self : NativeClientEffectSourceWork,
  retention : @resident.ResidentEffectReviewRetention,
  expected_revision : Int64,
  binding : @checkpoint.ResumeBinding,
  unknown_effects : Array[String],
) -> Result[NativeClientRunRecord, NativeClientEffectReviewWaitingIssue] {
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(Original(issue))
  }
  let persisted = match
    retention.confirm_original_checkpoint(
      self.owner,
      self.request,
      self.definition,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Retention(issue))
  }
  let observed_at = (self.current_time)()
  self.journal
  .wait_effect_checkpoint(
    self.request,
    self.allowed,
    persisted,
    expected_revision,
    binding,
    unknown_effects,
    observed_at,
    () => self.require_current() is Ok(_),
  )
  .map_err(issue => Journal(issue))
}
