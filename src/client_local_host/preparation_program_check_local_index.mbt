///|
/// Fund the original metadata/quotation packet on the SAME parent before
/// observing the original Local Source index geometry. No index or name admission runs here.
pub fn[I, P] inspect_program_check_source_local_index(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.phase == SourceLocalEntryPrepared {
    match reconcile_program_check_source_local_entry(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if !owner.busy && owner.phase == SourceLocalEntryRetained {
    owner.source_body_quote = None
    owner.phase = SourceLocalIndexInitial
  }
  guard !owner.busy &&
    (
      owner.phase == SourceLocalIndexInitial ||
      owner.phase == SourceLocalIndexObservationFunded
    ) &&
    owner.input is Some(input) &&
    owner.source_registration is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = inspect_program_check_source_local_index_owned(
    owner,
    input,
    @checked.parsed_source_registration_read(original),
  )
  owner.busy = false
  result
}

///|
fn[I, P] inspect_program_check_source_local_index_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  read : @context.SourceRegistrationRead,
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.phase == SourceLocalIndexInitial {
    let (r, e) = match
      @resources.preparation_capacity_working_extents(owner.capacity, input) {
      Err(issue) => return Err(Capacity(issue))
      Ok(value) => value
    }
    guard @execution.checked_preparation_add_product(
        r, program_source_local_index_metadata_peak_bytes, 1L,
      )
      is Some(r1) &&
      @execution.checked_preparation_add_product(
        e, program_source_local_index_metadata_peak_bytes, 1L,
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
      Ok(_) => owner.phase = SourceLocalIndexObservationFunded
    }
  }
  guard @context.source_registration_local_index_inspection_bound(read)
    is Some(maximum) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  let work = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.SourceLocalIndexInspection,
      maximum,
    ) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(value) => value
  }
  owner.work = Some(work)
  guard @context.observe_source_registration_local_index_construction(read)
    is Some(spent) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  match finish_program_check_source_work(owner, work, spent) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  owner.environment_scratch = Some(
    program_source_local_index_metadata_peak_bytes -
    program_source_local_index_metadata_retained_bytes,
  )
  owner.phase = SourceLocalIndexInspected
  Ok(())
}

///|
/// Original metadata is retained while only its returned walk scratch retires.
/// The quotation packet remains backed until actual Index construction has returned.
pub fn[I, P] reconcile_program_check_source_local_index_inspection(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  reconcile_program_check_environment_scratch(
    owner,
    SourceLocalIndexInspected,
    SourceLocalIndexMetadataRetained,
  )
}

///|
/// Quote and construct from the same read once. A failed grow retains its
/// original completed geometry and quote. RegistrationFailed is the original
/// semantic refusal state, not success or a generic implementation-limit tag.
pub fn[I, P] prepare_program_check_source_local_index(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[
  @context.SourceRegistrationPhase,
  ClientProgramCheckPreparationIssue,
] {
  if owner.phase == SourceLocalIndexInspected {
    match reconcile_program_check_source_local_index_inspection(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  guard !owner.busy &&
    owner.phase == SourceLocalIndexMetadataRetained &&
    owner.input is Some(input) &&
    owner.source_registration is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_program_check_source_local_index_owned(
    owner,
    input,
    @checked.parsed_source_registration_read(original),
  )
  owner.busy = false
  result
}

///|
fn[I, P] prepare_program_check_source_local_index_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  read : @context.SourceRegistrationRead,
) -> Result[
  @context.SourceRegistrationPhase,
  ClientProgramCheckPreparationIssue,
] {
  if owner.source_body_quote is None {
    guard program_source_local_index_body_bytes(read) is Some(quote) else {
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
  guard @context.source_registration_local_index_work_bound(read)
    is Some(maximum) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  let work = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.SourceLocalIndex,
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
  guard @context.source_registration_local_index_usage(read) is Some(usage) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  match finish_program_check_source_work(owner, work, usage.work.to_int64()) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match phase {
    RegistrationLocal => {
      owner.environment_scratch = Some(
        peak - held + program_source_local_index_quote_bytes,
      )
      owner.phase = SourceLocalIndexPrepared
      Ok(phase)
    }
    RegistrationFailed => {
      // The original typed issue/path can survive the failed reader. Keep its
      // entire peak until the original continuation is taken or cleared.
      owner.phase = SourceLocalIndexFailed
      Ok(phase)
    }
    _ => {
      owner.phase = Failed
      Err(WrongPhase)
    }
  }
}

///|
/// Success only: retain original Index/Usage and metadata. Drop returned
/// body/quotation scratch, never prior Source/Catalog backing or spent work.
pub fn[I, P] reconcile_program_check_source_local_index(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  reconcile_program_check_environment_scratch(
    owner,
    SourceLocalIndexPrepared,
    SourceLocalIndexRetained,
  )
}
