///|
/// A read of observations issued by the successful model owner. This opaque
/// handle is not constructible from a slot CID or a ModelCaptureBundle. It
/// retains private execution custody, not durable Store or egress authority.
pub struct VerifiedModelCapture {
  owner : ModelExecution
  mut released : Bool
}

///|
pub fn acquire_verified_model_capture(
  execution : ModelExecution,
) -> VerifiedModelCapture? {
  let state = execution.state
  if !state.accepted ||
    state.reclaimed ||
    state.call_scope is None ||
    state.output_uses == 2147483647 ||
    state.captures.length() != state.invocation_evidence.length() ||
    state.captures.length() != state.responses.length() {
    return None
  }
  state.output_uses += 1
  Some({ owner: execution, released: false, })
}

///|
pub fn release_verified_model_capture(capture : VerifiedModelCapture) -> Bool {
  if capture.released {
    return false
  }
  capture.released = true
  capture.owner.state.output_uses -= 1
  true
}

///|
pub fn retain_verified_model_capture(
  capture : VerifiedModelCapture,
) -> VerifiedModelCapture? {
  if capture.released {
    None
  } else {
    acquire_verified_model_capture(capture.owner)
  }
}

///|
/// The ordinary input must be prepared again under its new exact owner. Only
/// its canonical binding may match the saved call; physical owner equality
/// would incorrectly reject a reconstruction. No provider argument exists.
pub fn start_model_capture_replay(
  rows : @relation.PreparedInferRows,
  scope : @publication_host.ClientInferCallScope,
  capture : VerifiedModelCapture,
  limits : ModelExecutionLimits,
) -> Result[ModelExecution, ModelExecutionIssue] {
  let prior = capture.owner.state
  guard !capture.released &&
    prior.accepted &&
    !prior.reclaimed &&
    prior.call_scope is Some(prior_scope) &&
    prior.output_uses < 2147483647 else {
    return Err(OutputIdentity)
  }
  let task = @infer.model_task(@relation.prepared_infer_rows_owner(rows))
  if @environment.model_task_identity(task).2 !=
    @environment.model_task_identity(prior.task).2 ||
    @publication.run_evidence_value_identity(
      @publication_host.client_infer_call_scope_artifact(scope),
    ) !=
    @publication.run_evidence_value_identity(
      @publication_host.client_infer_call_scope_artifact(prior_scope),
    ) ||
    @relation.prepared_infer_rows_count(rows) != prior.captures.length() {
    return Err(OutputIdentity)
  }
  match
    start_model_owned(
      rows,
      Replay(capture),
      prior.fixed_request_cid,
      limits,
      Some(scope),
    ) {
    Err(issue) => Err(issue)
    Ok(value) => {
      // An active replay has its own read: releasing the caller's handle must
      // not release data that the resumed child still needs.
      prior.output_uses += 1
      Ok(value)
    }
  }
}

///|
// Called after the same bounded request preparation used by physical calls.
// Only the old owner can supply checked captures and invocation observations.
// Failure is terminal; there is deliberately no provider retry alternative.
fn advance_model_capture_replay(
  state : ModelState,
  capture : VerifiedModelCapture,
  prepared : PreparedModelRequest,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  let prior = capture.owner.state
  let request = prepared.request
  guard !prior.reclaimed &&
    prior.accepted &&
    prior.captures.get(state.next_slot) is Some(saved) &&
    prior.responses.get(state.next_slot) is Some(response) &&
    prior.invocation_evidence.get(state.next_slot) is Some(evidence) else {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  if saved.slot_cid != request.slot_cid ||
    saved.input_key_cid != prepared.key_cid ||
    saved.fixed_request_cid != request.fixed_request_cid ||
    saved.provider_id != @environment.model_task_connector(state.task) {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  state.captures.push(saved)
  state.responses.push(response)
  state.invocation_evidence.push(evidence)
  state.next_slot += 1
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
