///|
/// One remaining semantic phase on the SAME original registry/capacity.
/// Variable data uses the shared collection estimate; small controls use the
/// existing trusted Host overhead. No per-wrapper or per-operation callback.
pub fn[I, P] finish_program_check_preparation(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[@checked.CheckOutcome, ClientProgramCheckPreparationIssue] {
  if owner.effect_limits is Some(_) {
    return Err(WrongPhase)
  }
  if owner.phase == RequestsPrepared {
    match reconcile_program_check_requests(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  guard !owner.busy &&
    (owner.phase == RequestsRetained || owner.phase == SemanticCheckQuoted) &&
    owner.input is Some(input) &&
    owner.check_registry is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = finish_program_check_preparation_owned(owner, input, original)
  owner.busy = false
  result
}

///|
fn[I, P] finish_program_check_preparation_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  original : @checked.ParsedCheckRegistry,
) -> Result[@checked.CheckOutcome, ClientProgramCheckPreparationIssue] {
  let work = match begin_program_remaining_check(owner, input, original) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let calls = Ref(0L)
  let observed = @checked.observe_finish_parsed_check_registry(
    original,
    calls_out=Some(calls),
  )
  owner._observed_semantic_check_calls += calls.val
  let (outcome, spent, complete) = match observed {
    Err(issue) => {
      owner.phase = Failed
      return Err(Prelude(issue))
    }
    Ok(value) => value
  }
  let charged = @resources.spend_preparation_phase_work64(
    work,
    spent.to_int64(),
  )
  match @resources.finish_preparation_phase_work64(work) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(_) => owner.work = None
  }
  match charged {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(_) => ()
  }
  owner.check_outcome = Some(outcome)
  owner.check_work_complete = complete
  owner.phase = if outcome is @checked.Checked(_) {
    SemanticCheckComplete
  } else {
    SemanticCheckRejected
  }
  // Keep this single conservative data envelope with the original checked
  // output until the actual Plan/Run handoff or existing clear. No early refund.
  Ok(outcome)
}

///|
fn[I, P] begin_program_remaining_check(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  original : @checked.ParsedCheckRegistry,
) -> Result[
  @resources.PreparationPhaseWork64,
  ClientProgramCheckPreparationIssue,
] {
  if owner.phase == RequestsRetained {
    guard @checked.parsed_check_registry_data_estimate(original) is Some(data) &&
      program_check_data_extent_cost(data) is Some(bytes) else {
      return Err(Overflow)
    }
    let (r, e) = match
      @resources.preparation_capacity_working_extents(owner.capacity, input) {
      Err(issue) => return Err(Capacity(issue))
      Ok(value) => value
    }
    guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
      @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
      return Err(Overflow)
    }
    owner.check_data = Some(data)
    owner.check_quote = Some((r, e))
    owner.phase = SemanticCheckQuoted
  }
  let data = owner.check_data.unwrap()
  let (r, e) = owner.check_quote.unwrap()
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  // The external current callback may reenter or consume a borrowed original.
  // This cheap original-state check is not another external callback.
  guard @checked.parsed_check_registry_remaining_work(original) is Ok(remaining) &&
    remaining.to_int64() == data.semantic_work else {
    owner.phase = Failed
    return Err(ChangedInputs)
  }
  guard @execution.checked_preparation_add_product(
      data.semantic_work,
      data.inspection_work,
      1L,
    )
    is Some(maximum) else {
    return Err(Overflow)
  }
  let work = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.SemanticCheck,
      maximum,
    ) {
    Err(issue) => return Err(Work(issue))
    Ok(value) => value
  }
  owner.work = Some(work)
  match @resources.spend_preparation_phase_work64(work, data.inspection_work) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(_) => ()
  }
  Ok(work)
}

///|
/// Same original remaining semantic phase, retaining its typed Effect result.
pub fn[I, P] finish_effect_program_check_preparation(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[
  @checked.EffectComputationCandidate,
  ClientProgramCheckPreparationIssue,
] {
  if owner.phase == RequestsPrepared {
    match reconcile_program_check_requests(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  guard !owner.busy &&
    owner.effect_limits is Some(_) &&
    (owner.phase == RequestsRetained || owner.phase == SemanticCheckQuoted) &&
    owner.input is Some(input) &&
    owner.check_registry is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = finish_effect_program_check_preparation_owned(
    owner, input, original,
  )
  owner.busy = false
  result
}

///|
fn[I, P] finish_effect_program_check_preparation_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  original : @checked.ParsedCheckRegistry,
) -> Result[
  @checked.EffectComputationCandidate,
  ClientProgramCheckPreparationIssue,
] {
  let work = match begin_program_remaining_check(owner, input, original) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let (result, spent, complete) = @checked.observe_finish_parsed_effect_check_registry(
    original,
  )
  let charged = @resources.spend_preparation_phase_work64(
    work,
    spent.to_int64(),
  )
  match @resources.finish_preparation_phase_work64(work) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(_) => owner.work = None
  }
  match charged {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(_) => ()
  }
  owner.check_work_complete = complete
  match result {
    Err(issue) => {
      owner.phase = SemanticCheckRejected
      Err(EffectInput(issue))
    }
    Ok(candidate) => {
      owner.effect_candidate = Some(candidate)
      owner.phase = SemanticCheckComplete
      Ok(candidate)
    }
  }
}

///|
/// Transfer the SAME completed semantic DATA and its meter qualification.
/// No callback occurs between completion and this synchronous handoff. The
/// next consumer must keep the original capacity; this is no Run permission,
/// reservation release, or physical cleanup acknowledgement.
pub fn[I, P] take_program_check_preparation_outcome(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[(@checked.CheckOutcome, Bool), ClientProgramCheckPreparationIssue] {
  guard !owner.busy &&
    (
      owner.phase == SemanticCheckComplete ||
      owner.phase == SemanticCheckRejected
    ) &&
    owner.check_outcome is Some(outcome) else {
    return Err(WrongPhase)
  }
  let complete = owner.check_work_complete
  transfer_program_check_input(owner)
  Ok((outcome, complete))
}

///|
fn program_check_data_extent_cost(
  data : @checked.ParsedCheckDataEstimate,
) -> Int64? {
  guard @shape.collection_construction_extent(data.collections)
    is Some(collections) &&
    @execution.preparation_representation_cost({
      record_headers: collections.record_headers,
      reference_slots: collections.reference_slots,
      scalar_words: collections.scalar_words,
      owned_utf16_units: data.utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(bytes) else {
    return None
  }
  @execution.checked_preparation_add_product(
    bytes, program_topology_quotation_bytes, 1L,
  )
}
