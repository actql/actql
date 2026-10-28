///|
/// Fund the original metadata/quotation packet on the SAME parent before
/// observing the original collected Inputs and Catalog. No selection, NFC or permission lookup runs here.
pub fn[I, P] inspect_program_check_source_resolution(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.phase == SourceCollectionPrepared {
    match reconcile_program_check_source_collection(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if !owner.busy && owner.phase == SourceCollectionRetained {
    owner.source_body_quote = None
    owner.phase = SourceResolutionInitial
  }
  guard !owner.busy &&
    (
      owner.phase == SourceResolutionInitial ||
      owner.phase == SourceResolutionObservationFunded
    ) &&
    owner.input is Some(input) &&
    owner.source_registration is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = inspect_program_check_source_resolution_owned(
    owner,
    input,
    @checked.parsed_source_registration_read(original),
  )
  owner.busy = false
  result
}

///|
fn[I, P] inspect_program_check_source_resolution_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  read : @context.SourceRegistrationRead,
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.phase == SourceResolutionInitial {
    let (r, e) = match
      @resources.preparation_capacity_working_extents(owner.capacity, input) {
      Err(issue) => return Err(Capacity(issue))
      Ok(value) => value
    }
    guard @execution.checked_preparation_add_product(
        r, program_source_resolution_metadata_peak_bytes, 1L,
      )
      is Some(r1) &&
      @execution.checked_preparation_add_product(
        e, program_source_resolution_metadata_peak_bytes, 1L,
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
      Ok(_) => owner.phase = SourceResolutionObservationFunded
    }
  }
  guard @context.source_registration_resolution_inspection_bound(read)
    is Some(maximum) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  let work = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.SourceResolutionInspection,
      maximum,
    ) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(value) => value
  }
  owner.work = Some(work)
  guard @context.observe_source_registration_resolution_construction(read)
    is Some(spent) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  match finish_program_check_source_work(owner, work, spent) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  owner.environment_scratch = Some(
    program_source_resolution_metadata_peak_bytes -
    program_source_resolution_metadata_retained_bytes,
  )
  owner.phase = SourceResolutionInspected
  Ok(())
}

///|
/// Original metadata is retained while only its returned walk scratch retires.
/// The quotation packet remains backed until actual selection has returned.
pub fn[I, P] reconcile_program_check_source_resolution_inspection(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  reconcile_program_check_environment_scratch(
    owner,
    SourceResolutionInspected,
    SourceResolutionMetadataRetained,
  )
}

///|
/// Quote and construct from the same read once. A failed grow retains its
/// original completed geometry and quote. RegistrationFailed is the original
/// semantic refusal state, not success or a generic implementation-limit tag.
pub fn[I, P] prepare_program_check_source_resolution(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[
  @context.SourceRegistrationPhase,
  ClientProgramCheckPreparationIssue,
] {
  if owner.phase == SourceResolutionInspected {
    match reconcile_program_check_source_resolution_inspection(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  guard !owner.busy &&
    owner.phase == SourceResolutionMetadataRetained &&
    owner.input is Some(input) &&
    owner.source_registration is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_program_check_source_resolution_owned(
    owner,
    input,
    @checked.parsed_source_registration_read(original),
  )
  owner.busy = false
  result
}

///|
fn[I, P] prepare_program_check_source_resolution_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  read : @context.SourceRegistrationRead,
) -> Result[
  @context.SourceRegistrationPhase,
  ClientProgramCheckPreparationIssue,
] {
  if owner.source_body_quote is None {
    guard program_source_resolution_body_bytes(read) is Some(quote) else {
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
  guard @context.source_registration_resolution_work_bound(read)
    is Some(maximum) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  let work = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.SourceSelection,
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
      @context.source_registration_selection_work(read).to_int64(),
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match phase {
    RegistrationPipeline => {
      owner.environment_scratch = Some(
        peak - held + program_source_resolution_quote_bytes,
      )
      owner.phase = SourceResolutionPrepared
      Ok(phase)
    }
    RegistrationFailed => {
      // The original typed issue/path can survive the failed reader. Keep its
      // entire peak until the original continuation is taken or cleared.
      owner.phase = SourceResolutionFailed
      Ok(phase)
    }
    _ => {
      owner.phase = Failed
      Err(WrongPhase)
    }
  }
}

///|
/// Success only: retain original Resolved/NFC/URI bodies and metadata. Drop returned
/// body/quotation scratch, never prior Source/Catalog backing or spent work.
pub fn[I, P] reconcile_program_check_source_resolution(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  reconcile_program_check_environment_scratch(
    owner,
    SourceResolutionPrepared,
    SourceResolutionRetained,
  )
}
