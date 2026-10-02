///|
/// Private stopped-execution custody, including strict failure or cancellation.
/// An adopted prefix is not a complete ObservationSet or an accepted output.
pub struct ModelOutcomeRead {
  owner : ModelExecution
  mut released : Bool
}

///|
pub fn acquire_model_outcomes(execution : ModelExecution) -> ModelOutcomeRead? {
  let state = execution.state
  if state.reclaimed ||
    !@bounded.session_stopped(execution.session) ||
    state.output_uses == 2147483647 {
    return None
  }
  state.output_uses += 1
  Some({ owner: execution, released: false, })
}

///|
pub fn model_outcomes_accepted(read : ModelOutcomeRead) -> Bool {
  !read.released && !read.owner.state.reclaimed && read.owner.state.accepted
}

///|
/// Count only actually adopted slots, not all prepared or reserved requests.
pub fn model_outcomes_count(read : ModelOutcomeRead) -> Int? {
  if read.released || read.owner.state.reclaimed {
    None
  } else {
    Some(read.owner.state.outcomes.length())
  }
}

///|
pub fn model_outcomes_outcome(read : ModelOutcomeRead, slot : Int) -> String? {
  if read.released || read.owner.state.reclaimed {
    None
  } else {
    read.owner.state.outcomes.get(slot).map(adopted_model_slot_outcome)
  }
}

///|
pub fn model_outcomes_call_at(
  read : ModelOutcomeRead,
  slot : Int,
) -> @publication.RunEvidenceValue? {
  let state = read.owner.state
  guard !read.released &&
    !state.reclaimed &&
    state.outcomes.get(slot) is Some(_) &&
    state.requests.get(slot) is Some(prepared) &&
    prepared.call is Some(call) &&
    prepared.request.slot == slot &&
    prepared.request.slot_cid == @publication.run_evidence_value_identity(call) else {
    return None
  }
  Some(call)
}

///|
pub fn model_outcomes_invocation_evidence(
  read : ModelOutcomeRead,
  slot : Int,
) -> @publication.RunEvidenceValue? {
  guard !read.released &&
    !read.owner.state.reclaimed &&
    read.owner.state.outcomes.get(slot) is Some(Success(index)) else {
    return None
  }
  read.owner.state.invocation_evidence.get(index)
}

///|
pub fn retain_model_outcomes(read : ModelOutcomeRead) -> ModelOutcomeRead? {
  if read.released {
    None
  } else {
    acquire_model_outcomes(read.owner)
  }
}

///|
pub fn release_model_outcomes(read : ModelOutcomeRead) -> Bool {
  if read.released {
    return false
  }
  read.released = true
  read.owner.state.output_uses -= 1
  true
}
