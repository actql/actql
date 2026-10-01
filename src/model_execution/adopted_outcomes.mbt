///|
fn model_failure_outcome(failure : ModelProviderFailure) -> String? {
  match failure {
    RateLimit => Some("failed:rate_limit")
    Timeout => Some("failed:timeout")
    ProviderError => Some("failed:provider_error")
    Refusal => Some("failed:refusal")
    SchemaInvalid => Some("failed:schema_invalid")
    SafetyRejected => Some("failed:safety_rejected")
    Truncated => Some("failed:truncated")
    Cancelled => None
  }
}

///|
fn adopted_model_slot_outcome(slot : AdoptedModelSlot) -> String {
  match slot {
    Success(_) => "ok"
    NoResponseFailure(failure) => model_failure_outcome(failure).unwrap()
  }
}

///|
// A classified physical failure is adopted once. It is not an invented
// response, an authorization failure or an implicit retry instruction.
fn accept_failed_model_slot(
  state : ModelState,
  failure : ModelProviderFailure,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  if model_failure_outcome(failure) is None {
    return @bounded.Failed(Provider(failure), 1, 1)
  }
  state.outcomes.push(NoResponseFailure(failure))
  state.next_slot += 1
  state.phase = DispatchSlot
  if @infer.result_mode(@relation.prepared_infer_rows_owner(state.rows)) is Fail {
    // Prior and current observations remain private until cleanup; no output
    // is accepted, and later unattempted slots are not fabricated failures.
    return @bounded.Failed(Provider(failure), 1, 1)
  }
  if state.next_slot == @relation.prepared_infer_rows_count(state.rows) {
    @bounded.Complete(
      {
        task_cid: @environment.model_task_identity(state.task).2,
        fixed_request_cid: state.fixed_request_cid,
        captures: state.captures.copy(),
      },
      1,
      1,
    )
  } else {
    @bounded.Continue(1, 1)
  }
}

///|
/// Outcome at a logical call position, including response-less failures. An
/// equal caller-authored bundle or CID cannot supply this owner observation.
pub fn verified_model_capture_outcome(
  capture : VerifiedModelCapture,
  slot : Int,
) -> String? {
  if capture.released ||
    !capture.owner.state.accepted ||
    capture.owner.state.reclaimed {
    None
  } else {
    capture.owner.state.outcomes.get(slot).map(adopted_model_slot_outcome)
  }
}
