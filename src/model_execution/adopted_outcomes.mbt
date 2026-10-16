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
    UnresolvedUnknown => "result_unknown"
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
  adopt_model_outcome(state, NoResponseFailure(failure))
  if state.attempts.get(state.progress.slot) is Some(trace) {
    trace.category = "provider_failure"
    trace.failure = model_failure_outcome(failure).map(value => {
      value[7:].to_owned()
    })
    trace.work = state.work
  }
  if state.durable_calls {
    state.progress.settlement = Some(state.progress.slot)
  }
  state.progress.slot += 1
  state.progress.phase = DispatchSlot
  if @infer.result_mode(@relation.prepared_infer_rows_owner(state.rows)) is Fail {
    // Prior and current observations remain private until cleanup; no output
    // is accepted, and later unattempted slots are not fabricated failures.
    return @bounded.Failed(Provider(failure), 1, 1)
  }
  if state.progress.slot == @relation.prepared_infer_rows_count(state.rows) {
    complete_model_slots(state)
  } else {
    @bounded.Continue(1, 1)
  }
}

///|
fn complete_model_slots(
  state : ModelState,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  if order_model_window_outcomes(state) is Some(step) {
    return step
  }
  if state.durable_calls && state.progress.settlement is Some(_) {
    return @bounded.Continue(1, 1)
  }
  if !state.unknown_calls.is_empty() {
    return @bounded.Failed(UnknownCalls, 1, 1)
  }
  if state.source is RestoredSlots(read) {
    guard model_slot_replay_count(read) == Some(state.progress.slot) &&
      read.storage.bundle is Some(bundle) &&
      @publication.model_capture_bundle_count(bundle) == state.captures.length() else {
      return @bounded.Failed(OutputIdentity, 1, 1)
    }
  }
  let captures = match state.slot_window {
    Some(window) => {
      guard window.export_captures is Some(exported) &&
        exported.length() == state.captures.length() else {
        return @bounded.Failed(OutputIdentity, 1, 1)
      }
      // This is the already built logical DATA projection, not a sort or a
      // mutation of the original arrival-indexed nominal observations.
      window.export_captures = None
      exported
    }
    None => state.captures.copy()
  }
  @bounded.Complete(
    {
      task_cid: @environment.model_task_identity(state.task).2,
      fixed_request_cid: state.fixed_request_cid,
      captures,
    },
    1,
    1,
  )
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
    model_outcome_at(capture.owner.state, slot).map(adopted_model_slot_outcome)
  }
}
