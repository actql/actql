///|
pub(all) enum NativeResidentEffectReviewPreparationIssue {
  Unavailable
  Result(@resident.ResidentEffectResultCaptureIssue)
  Review(NativeResidentEffectReviewIssue)
}

///|
/// Preparation consumes the input context. A failed cleanup retains that exact
/// context for retry; the original Source/Runtime/Transfer stay separately owned.
pub(all) struct NativeResidentEffectReviewPreparationFailure {
  issue : NativeResidentEffectReviewPreparationIssue
  pending : @resident.ResidentEffectReviewInputContext?
}

///|
fn reject_resident_effect_review_context(
  context : @resident.ResidentEffectReviewInputContext,
  issue : NativeResidentEffectReviewPreparationIssue,
) -> Result[
  NativeResidentEffectReview,
  NativeResidentEffectReviewPreparationFailure,
] {
  let pending = if context.close() { None } else { Some(context) }
  Err({ issue, pending, })
}

///|
/// Transfer the actual-holder context to this review adapter before preparing
/// its Result export. Successful preparation owns both until review obligations
/// are discharged and cleanup is confirmed. No Source acquisition, Compute
/// execution, Provider access, approval or new physical holding occurs here. Trusted Host normalization
/// metadata and independently installed Provider policy are still required.
pub fn prepare_native_resident_effect_review_from_context(
  holder : @resident.ResidentRetainedConsumer,
  journal : @journal.Journal,
  context : @resident.ResidentEffectReviewInputContext,
  normalization : @publication.RunEvidenceValue,
  binding_names : Array[String],
  binding_digests : Array[String],
  policy : NativeResidentEffectReviewPolicy,
) -> Result[
  NativeResidentEffectReview,
  NativeResidentEffectReviewPreparationFailure,
] {
  guard context.matches_holder(holder, journal) &&
    context.retention_matches(policy.retention) &&
    context.facts(journal) is Some(facts) else {
    return reject_resident_effect_review_context(context, Unavailable)
  }
  let limits = policy.preview_limits
  let result = match
    context.capture_result(
      journal,
      normalization,
      binding_names,
      binding_digests,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) =>
      return reject_resident_effect_review_context(context, Result(issue))
  }
  let work = match
    prepare_native_resident_effect_review(
      holder,
      journal,
      facts.materials,
      facts.inputs,
      facts.producer,
      facts.receiver,
      facts.imported,
      facts.root_index,
      result,
      facts.producer.invocation,
      facts.producer.observation,
      policy,
    ) {
    Ok(value) => value
    Err(issue) => {
      result.output.cancel()
      return reject_resident_effect_review_context(context, Review(issue))
    }
  }
  work.owned_inputs = Some(context)
  work.owned_result = true
  Ok(work)
}

///|
/// Borrow the actual completed consumer Result while review custody is live.
/// Its export stays review-owned; callers must not cancel or transfer it.
pub fn NativeResidentEffectReview::result_capture(
  self : NativeResidentEffectReview,
) -> @resident.ResidentEffectResultCapture? {
  if self.current() {
    Some(self.result)
  } else {
    None
  }
}

///|
/// The exact dispatch remains the key for the CLI's existing task custody.
/// This projection grants no approval, release or current Provider permission.
pub fn NativeResidentEffectReview::dispatch_identity(
  self : NativeResidentEffectReview,
) -> String {
  @remote.dispatch_request_identity(
    @resident.resident_retained_consumer_request(self.holder),
  )
}
