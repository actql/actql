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
  if check_model_original_resources_mutable(state) is Err(_) {
    return None
  }
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
    Some(model_outcome_count(read.owner.state))
  }
}

///|
/// Logical Slot at an actually adopted observation position. Parallel arrival
/// can be sparse after stop: count2 does not imply logical Slots0 and1.
pub fn model_outcomes_slot_at(read : ModelOutcomeRead, index : Int) -> Int? {
  if read.released || read.owner.state.reclaimed || index < 0 {
    return None
  }
  match read.owner.state.slot_window {
    Some(window) => window.adopted_slots.get(index)
    None =>
      if index < read.owner.state.outcomes.length() {
        Some(index)
      } else {
        None
      }
  }
}

///|
pub fn model_outcomes_outcome(read : ModelOutcomeRead, slot : Int) -> String? {
  if read.released || read.owner.state.reclaimed {
    None
  } else {
    model_outcome_at(read.owner.state, slot).map(adopted_model_slot_outcome)
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
    model_outcome_at(state, slot) is Some(_) &&
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
    model_outcome_at(read.owner.state, slot) is Some(Success(index)) else {
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
  if check_model_original_resources_mutable(read.owner.state) is Err(_) {
    return false
  }
  read.released = true
  read.owner.state.output_uses -= 1
  true
}
