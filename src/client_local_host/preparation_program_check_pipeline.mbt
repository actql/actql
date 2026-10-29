///|
/// Fund only the O(1) quotation entrance first, then its original Stage/entry
/// bodies on the SAME capacity. No new Source/Catalog walk or Local read runs.
/// A failed grow keeps its phase and original quote; no completed work repeats.
pub fn[I, P] prepare_program_check_source_pipeline(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[
  @context.SourceRegistrationPhase,
  ClientProgramCheckPreparationIssue,
] {
  if owner.phase == SourceResolutionPrepared {
    match reconcile_program_check_source_resolution(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if !owner.busy && owner.phase == SourceResolutionRetained {
    owner.source_body_quote = None
    owner.phase = SourcePipelineInitial
  }
  guard !owner.busy &&
    (
      owner.phase == SourcePipelineInitial ||
      owner.phase == SourcePipelineQuoted
    ) &&
    owner.input is Some(input) &&
    owner.source_registration is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_program_check_source_pipeline_owned(
    owner,
    input,
    @checked.parsed_source_registration_read(original),
  )
  owner.busy = false
  result
}

///|
fn[I, P] prepare_program_check_source_pipeline_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  read : @context.SourceRegistrationRead,
) -> Result[
  @context.SourceRegistrationPhase,
  ClientProgramCheckPreparationIssue,
] {
  if owner.phase == SourcePipelineInitial {
    let (r, e) = match
      @resources.preparation_capacity_working_extents(owner.capacity, input) {
      Err(issue) => return Err(Capacity(issue))
      Ok(value) => value
    }
    guard @execution.checked_preparation_add_product(
        r, program_source_pipeline_quote_bytes, 1L,
      )
      is Some(r1) &&
      @execution.checked_preparation_add_product(
        e, program_source_pipeline_quote_bytes, 1L,
      )
      is Some(e1) else {
      return Err(Overflow)
    }
    match
      @resources.reserve_working_preparation_phase(
        owner.capacity,
        input,
        r1,
        e1,
      ) {
      Err(issue) => return Err(Capacity(issue))
      Ok(_) => owner.phase = SourcePipelineQuoted
    }
  }
  if owner.source_body_quote is None {
    guard program_source_pipeline_body_bytes(read) is Some(quote) else {
      return Err(Overflow)
    }
    owner.source_body_quote = Some(quote)
  }
  let (peak, held) = owner.source_body_quote.unwrap()
  let (r, e) = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(r, peak, 1L) is Some(r1) &&
    @execution.checked_preparation_add_product(e, peak, 1L) is Some(e1) else {
    return Err(Overflow)
  }
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r1, e1) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard @context.source_registration_pipeline_work_bound(read) is Some(maximum) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  let work = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.SourcePipelineRegistration,
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
  match
    finish_program_check_source_work(
      owner,
      work,
      @context.source_registration_pipeline_work(read).to_int64(),
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match phase {
    RegistrationLocal => {
      owner.environment_scratch = Some(
        peak - held + program_source_pipeline_quote_bytes,
      )
      owner.phase = SourcePipelinePrepared
      Ok(phase)
    }
    RegistrationFailed => {
      owner.phase = SourcePipelineFailed
      Ok(phase)
    }
    _ => {
      owner.phase = Failed
      Err(WrongPhase)
    }
  }
}

///|
/// Keep the original PipelineInputs and all prior Source/Catalog bodies.
/// Only returned quotation/body scratch retires; nested Local is still pending.
pub fn[I, P] reconcile_program_check_source_pipeline(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  reconcile_program_check_environment_scratch(
    owner,
    SourcePipelinePrepared,
    SourcePipelineRetained,
  )
}
