///|
/// A read of outcomes issued by the accepted model owner. This opaque
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
    state.requests.length() != @relation.prepared_infer_rows_count(state.rows) ||
    state.requests.length() != state.outcomes.length() ||
    state.captures.length() != state.invocation_evidence.length() ||
    state.captures.length() != state.responses.length() {
    return None
  }
  state.output_uses += 1
  Some({ owner: execution, released: false, })
}

///|
/// Complete call inventory from the accepted execution's canonical typed-key
/// order. This is not a caller-provided count or a successful-bundle subset.
/// Strict failed barriers have no accepted capture; their private outcome owner must
/// retain responsibility separately rather than inventing unattempted slots.
pub fn verified_model_capture_call_count(
  capture : VerifiedModelCapture,
) -> Int? {
  let state = capture.owner.state
  if capture.released || !state.accepted || state.reclaimed {
    None
  } else {
    Some(state.requests.length())
  }
}

///|
/// Retain the exact pre-dispatch call body so the adopting capture owner can
/// bind its record without reconstructing a call from response metadata.
/// Reading one call does not hash a key or traverse an input again.
pub fn verified_model_capture_call_at(
  capture : VerifiedModelCapture,
  slot : Int,
) -> @publication.RunEvidenceValue? {
  let state = capture.owner.state
  guard !capture.released &&
    state.accepted &&
    !state.reclaimed &&
    state.requests.get(slot) is Some(prepared) &&
    prepared.call is Some(call) &&
    prepared.request.slot == slot &&
    prepared.request.slot_cid == @publication.run_evidence_value_identity(call) &&
    state.outcomes.get(slot) is Some(_) else {
    return None
  }
  Some(call)
}

///|
/// Bind against the actual accepted execution, not a supplied call list or
/// successful-response bundle. This does not adopt attempts or verify external
/// policy/accounting/authority references; the formal capture owner owns those.
pub fn bind_verified_model_slot_capture(
  capture : VerifiedModelCapture,
  slot : Int,
  record : @publication.RunEvidenceValue,
) -> Result[@publication.BoundModelSlotCapture, ModelExecutionIssue] {
  guard verified_model_capture_call_at(capture, slot) is Some(call) &&
    capture.owner.state.outcomes.get(slot) is Some(outcome) else {
    return Err(OutputIdentity)
  }
  let binding = match @publication.bind_model_slot_capture(call, record) {
    Ok(value) => value
    Err(issue) => return Err(InvocationEvidence(issue))
  }
  if capture.owner.state.dispatch_admission is Some(_) {
    let issued = match
      model_execution_issued_slot_capture(capture.owner, slot) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if @publication.run_evidence_value_identity(issued) !=
      @publication.run_evidence_value_identity(record) {
      return Err(OutputIdentity)
    }
  }
  let verified = match outcome {
    Success(index) => {
      guard capture.owner.state.invocation_evidence.get(index)
        is Some(observation) else {
        return Err(OutputIdentity)
      }
      @publication.verify_model_slot_success_observation(binding, observation)
    }
    NoResponseFailure(_) =>
      @publication.verify_model_slot_no_response_failure(
        binding,
        adopted_model_slot_outcome(outcome),
      )
  }
  verified.map(_ => binding).map_err(issue => InvocationEvidence(issue))
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
/// Obtain the actual adopted proof record for physical execution or verified
/// saved replay. Legacy structural reads cannot become publication evidence.
pub fn verified_model_capture_owned_slot(
  capture : VerifiedModelCapture,
  slot : Int,
) -> Result[@publication.RunEvidenceValue, ModelExecutionIssue] {
  guard verified_model_capture_call_at(capture, slot) is Some(call) else {
    return Err(OutputIdentity)
  }
  let state = capture.owner.state
  if state.dispatch_admission is Some(_) {
    return model_execution_issued_slot_capture(capture.owner, slot)
  }
  guard state.source is RestoredSlots(read) && read.storage.proofs is Some(_) else {
    return Err(OutputIdentity)
  }
  let binding = match
    restored_slot_binding(
      read,
      slot,
      call,
      @environment.model_task_data_handling_cid(state.task),
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let record = @publication.bound_model_slot_capture_value(binding)
  bind_verified_model_slot_capture(capture, slot, record).map(_ => record)
}

///|
/// Zero-key publication needs the same checked source mode as nonempty input;
/// it cannot promote a legacy structural replay merely by visiting no slots.
pub fn model_execution_has_adopted_evidence(execution : ModelExecution) -> Bool {
  let state = execution.state
  if !state.accepted || state.reclaimed {
    return false
  }
  if state.dispatch_admission is Some(_) {
    return true
  }
  state.source is RestoredSlots(read) &&
  read.storage.proofs is Some(_) &&
  read.storage.saved_admission is Some(_) &&
  read.storage.saved_definition is Some(_)
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
    @relation.prepared_infer_rows_count(rows) != prior.outcomes.length() {
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
    prior.requests.get(state.next_slot) is Some(prior_request) &&
    prior.outcomes.get(state.next_slot) is Some(outcome) else {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  if prior_request.request.slot_cid != request.slot_cid ||
    prior_request.key_cid != prepared.key_cid ||
    prior_request.request.fixed_request_cid != request.fixed_request_cid {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  if outcome is NoResponseFailure(failure) {
    return accept_failed_model_slot(state, failure)
  }
  guard outcome is Success(index) &&
    prior.captures.get(index) is Some(saved) &&
    prior.responses.get(index) is Some(response) &&
    prior.invocation_evidence.get(index) is Some(evidence) else {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  if saved.slot_cid != request.slot_cid ||
    saved.input_key_cid != prepared.key_cid ||
    saved.fixed_request_cid != request.fixed_request_cid ||
    saved.provider_id != @environment.model_task_connector(state.task) {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  state.captures.push(saved)
  state.outcomes.push(Success(state.responses.length()))
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
