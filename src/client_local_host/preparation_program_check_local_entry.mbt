///|
let program_source_local_entry_bytes : Int64 = program_source_extent_cost(
  @context.source_registration_local_entry_extent(),
).unwrap()

///|
let program_source_local_entry_retained_bytes : Int64 = program_source_extent_cost(
  @context.source_registration_local_entry_retained_extent(),
).unwrap()

///|
/// Create only the SAME read's original Local child after backing its entry.
/// The completed Source/Resolved/Pipeline bodies and capacity remain original.
/// Index and member constructors are pending, not covered by this small packet.
pub fn[I, P] prepare_program_check_source_local_entry(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[
  @context.SourceRegistrationPhase,
  ClientProgramCheckPreparationIssue,
] {
  if owner.phase == SourcePipelinePrepared {
    match reconcile_program_check_source_pipeline(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  guard !owner.busy &&
    owner.phase == SourcePipelineRetained &&
    owner.input is Some(input) &&
    owner.source_registration is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_program_check_source_local_entry_owned(
    owner,
    input,
    @checked.parsed_source_registration_read(original),
  )
  owner.busy = false
  result
}

///|
fn[I, P] prepare_program_check_source_local_entry_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  read : @context.SourceRegistrationRead,
) -> Result[
  @context.SourceRegistrationPhase,
  ClientProgramCheckPreparationIssue,
] {
  let (r, e) = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(
      r, program_source_local_entry_bytes, 1L,
    )
    is Some(r1) &&
    @execution.checked_preparation_add_product(
      e, program_source_local_entry_bytes, 1L,
    )
    is Some(e1) else {
    return Err(Overflow)
  }
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r1, e1) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard @context.source_registration_local_entry_work_bound(read)
    is Some(maximum) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  let work = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.SourceLocalEntry,
      maximum.to_int64(),
    ) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(value) => value
  }
  owner.work = Some(work)
  let phase = @context.advance_source_registration(read)
  guard @context.source_registration_local_entry_work(read) is Some(spent) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  match finish_program_check_source_work(owner, work, spent.to_int64()) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match phase {
    RegistrationLocal => {
      owner.environment_scratch = Some(
        program_source_local_entry_bytes -
        program_source_local_entry_retained_bytes,
      )
      owner.phase = SourceLocalEntryPrepared
      Ok(phase)
    }
    RegistrationFailed => {
      // Original refusal retains its full entry peak; missing later child
      // work is never replaced with zero or a completed preparation claim.
      owner.phase = SourceLocalEntryFailed
      Ok(phase)
    }
    _ => {
      owner.phase = Failed
      Err(WrongPhase)
    }
  }
}

///|
pub fn[I, P] reconcile_program_check_source_local_entry(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  reconcile_program_check_environment_scratch(
    owner,
    SourceLocalEntryPrepared,
    SourceLocalEntryRetained,
  )
}
