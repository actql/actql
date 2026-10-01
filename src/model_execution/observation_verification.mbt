///|
/// Installed admission ceilings, not new restrictions on INFER semantics.
/// The per-record wire ceiling bounds the existing flat structural matcher
/// inside one step; the complete call inventory is never drained in a step.
pub(all) struct ModelObservationVerificationLimits {
  max_slots : Int
  max_slot_wire_units : Int
  max_work : Int
}

///|
struct ModelObservationVerificationState {
  capture : VerifiedModelCapture
  observation : @publication.RunEvidenceValue
  mut records : Array[@publication.RunEvidenceValue]
  count : Int
  limits : ModelObservationVerificationLimits
  mut index : Int
  mut work : Int
}

///|
/// Exact observation-to-execution matching, not authority or durable capture
/// confirmation. Attempt, policy, accounting and private Store records still
/// require their respective owners before Run publication may proceed.
pub struct ModelObservationVerification {
  state : ModelObservationVerificationState
  session : @bounded.Session[
    ModelObservationVerificationState,
    Unit,
    ModelExecutionIssue,
  ]
  control : @bounded.Control
  mut token : @bounded.Token
  mut accepted : Bool
  mut reclaimed : Bool
}

///|
pub fn start_model_observation_verification(
  capture : VerifiedModelCapture,
  observation : @publication.RunEvidenceValue,
  records : Array[@publication.RunEvidenceValue],
  limits : ModelObservationVerificationLimits,
) -> Result[ModelObservationVerification, ModelExecutionIssue] {
  if limits.max_slots < 0 ||
    limits.max_slot_wire_units < 1 ||
    limits.max_work < 1 {
    return Err(InvalidLimits)
  }
  guard verified_model_capture_call_count(capture) is Some(count) else {
    return Err(OutputIdentity)
  }
  if count > limits.max_slots {
    return Err(ItemLimit)
  }
  if records.length() != count ||
    @publication.model_observation_slot_count(observation) != Some(count) {
    return Err(
      InvocationEvidence(
        @publication.RunEvidenceReferenceMismatch("model_slot_capture_cids"),
      ),
    )
  }
  guard retain_verified_model_capture(capture) is Some(retained) else {
    return Err(OutputIdentity)
  }
  // Admission retains no second whole inventory or response array. Each
  // immutable record is checked against the owner's logical slot on demand.
  let state : ModelObservationVerificationState = {
    capture: retained,
    observation,
    records,
    count,
    limits,
    index: 0,
    work: 0,
  }
  let control = @bounded.control()
  let (session, token) = @bounded.start(
    control,
    state,
    advance_model_observation_verification_step,
    _ => true,
    _ => true,
  )
  Ok({ state, session, control, token, accepted: false, reclaimed: false, })
}

///|
fn advance_model_observation_verification_step(
  state : ModelObservationVerificationState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[Unit, ModelExecutionIssue] {
  if @bounded.stop_requested(reader) is Some(reason) {
    return @bounded.Stopped(reason, 0, 0)
  }
  if quantum < 1 {
    return @bounded.Failed(InvalidLimits, 0, 0)
  }
  if state.work >= state.limits.max_work {
    return @bounded.Failed(WorkLimit, 0, 0)
  }
  state.work += 1
  if verified_model_capture_call_count(state.capture) != Some(state.count) ||
    state.records.length() != state.count {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  if state.index == state.count {
    return @bounded.Complete((), 1, 1)
  }
  let record = state.records[state.index]
  if @publication.run_evidence_value_json(record).length() >
    state.limits.max_slot_wire_units {
    return @bounded.Failed(RequestLimit, 1, 1)
  }
  match bind_verified_model_slot_capture(state.capture, state.index, record) {
    Err(issue) => return @bounded.Failed(issue, 1, 1)
    Ok(_) => ()
  }
  if @publication.model_observation_slot_at(state.observation, state.index) !=
    Some(@publication.run_evidence_value_identity(record)) {
    return @bounded.Failed(
      InvocationEvidence(
        @publication.RunEvidenceReferenceMismatch("model_slot_capture_cids"),
      ),
      1,
      1,
    )
  }
  state.index += 1
  @bounded.Continue(1, 1)
}

///|
pub fn advance_model_observation_verification(
  active : ModelObservationVerification,
  quantum : Int,
) -> Result[(Bool, Int64), ModelExecutionIssue] {
  match @bounded.advance(active.session, active.token, quantum) {
    Err(issue) => Err(Session(issue))
    Ok(@bounded.ContinueWith(token, work~, ..)) => {
      active.token = token
      Ok((false, work))
    }
    Ok(@bounded.Completed(_, work~, ..)) => {
      active.accepted = true
      Ok((true, work))
    }
    Ok(@bounded.FailedWith(issue, ..)) => Err(issue)
    Ok(@bounded.StoppedWith(_, ..)) => Err(Cancelled)
  }
}

///|
pub fn model_observation_verification_value(
  active : ModelObservationVerification,
) -> @publication.RunEvidenceValue? {
  if active.accepted && !active.reclaimed {
    Some(active.state.observation)
  } else {
    None
  }
}

///|
pub fn cancel_model_observation_verification(
  active : ModelObservationVerification,
) -> Bool {
  if active.reclaimed || @bounded.session_stopped(active.session) {
    false
  } else {
    @bounded.request_cancel(active.control)
  }
}

///|
pub fn cleanup_model_observation_verification(
  active : ModelObservationVerification,
) -> Result[Bool, ModelExecutionIssue] {
  if active.reclaimed {
    return Ok(true)
  }
  if !@bounded.session_stopped(active.session) {
    return Ok(false)
  }
  match @bounded.cleanup(active.session) {
    Err(issue) => Err(Session(issue))
    Ok(false) => Ok(false)
    Ok(true) => {
      // Drop our reference, not the caller's array or independently held read.
      active.state.records = []
      release_verified_model_capture(active.state.capture) |> ignore
      active.reclaimed = true
      Ok(true)
    }
  }
}
