///|
/// Fund the original metadata/quotation packet on the SAME parent before
/// walking the original Source. No semantic collection or Catalog read here.
pub fn[I, P] inspect_program_check_source_collection(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.phase == SourceRegistrationPrepared {
    match reconcile_program_check_source_registration(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  guard !owner.busy &&
    (
      owner.phase == SourceRegistrationRetained ||
      owner.phase == SourceCollectionObservationFunded
    ) &&
    owner.input is Some(input) &&
    owner.source_registration is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = inspect_program_check_source_collection_owned(
    owner,
    input,
    @checked.parsed_source_registration_read(original),
  )
  owner.busy = false
  result
}

///|
fn[I, P] inspect_program_check_source_collection_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  read : @context.SourceRegistrationRead,
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.phase == SourceRegistrationRetained {
    let (r, e) = match
      @resources.preparation_capacity_working_extents(owner.capacity, input) {
      Err(issue) => return Err(Capacity(issue))
      Ok(value) => value
    }
    guard @execution.checked_preparation_add_product(
        r, program_source_collection_metadata_peak_bytes, 1L,
      )
      is Some(r1) &&
      @execution.checked_preparation_add_product(
        e, program_source_collection_metadata_peak_bytes, 1L,
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
      Ok(_) => owner.phase = SourceCollectionObservationFunded
    }
  }
  guard @context.source_registration_collection_inspection_bound(read)
    is Some(maximum) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  let work = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.SourceCollectionInspection,
      maximum,
    ) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(value) => value
  }
  owner.work = Some(work)
  guard @context.observe_source_registration_collection_construction(read)
    is Some(spent) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  match finish_program_check_source_work(owner, work, spent) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  owner.environment_scratch = Some(
    program_source_collection_metadata_peak_bytes -
    program_source_collection_metadata_retained_bytes,
  )
  owner.phase = SourceCollectionInspected
  Ok(())
}

///|
/// Original metadata is retained while only its returned walk scratch retires.
/// The quotation packet remains backed until actual collection has returned.
pub fn[I, P] reconcile_program_check_source_collection_inspection(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  reconcile_program_check_environment_scratch(
    owner,
    SourceCollectionInspected,
    SourceCollectionMetadataRetained,
  )
}

///|
/// Quote and construct from the same read once. A failed grow retains its
/// original completed geometry and quote. RegistrationFailed is the original
/// semantic refusal state, not success or a generic implementation-limit tag.
pub fn[I, P] prepare_program_check_source_collection(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[
  @context.SourceRegistrationPhase,
  ClientProgramCheckPreparationIssue,
] {
  if owner.phase == SourceCollectionInspected {
    match reconcile_program_check_source_collection_inspection(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  guard !owner.busy &&
    owner.phase == SourceCollectionMetadataRetained &&
    owner.input is Some(input) &&
    owner.source_registration is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_program_check_source_collection_owned(
    owner,
    input,
    @checked.parsed_source_registration_read(original),
  )
  owner.busy = false
  result
}

///|
fn[I, P] prepare_program_check_source_collection_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  read : @context.SourceRegistrationRead,
) -> Result[
  @context.SourceRegistrationPhase,
  ClientProgramCheckPreparationIssue,
] {
  if owner.source_body_quote is None {
    guard program_source_collection_body_bytes(read) is Some(quote) else {
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
  guard @context.source_registration_collection_work_bound(read)
    is Some(maximum) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  let work = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.SourceCollection,
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
      @context.source_registration_collection_work(read).to_int64(),
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match phase {
    RegistrationSelect => {
      owner.environment_scratch = Some(
        peak - held + program_source_collection_quote_bytes,
      )
      owner.phase = SourceCollectionPrepared
      Ok(phase)
    }
    RegistrationFailed => {
      // The original typed issue/path can survive the failed reader. Keep its
      // entire peak until the original continuation is taken or cleared.
      owner.phase = SourceCollectionFailed
      Ok(phase)
    }
    _ => {
      owner.phase = Failed
      Err(WrongPhase)
    }
  }
}

///|
fn[I, P] finish_program_check_source_work(
  owner : ClientProgramCheckPreparation[I, P],
  work : @resources.PreparationPhaseWork64,
  amount : Int64,
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  let charged = @resources.spend_preparation_phase_work64(work, amount)
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
      Err(Work(issue))
    }
    Ok(_) => Ok(())
  }
}

///|
/// Success only: retain original Inputs/NFC bodies and metadata. Drop returned
/// body/quotation scratch, never prior Source/Catalog backing or spent work.
pub fn[I, P] reconcile_program_check_source_collection(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  reconcile_program_check_environment_scratch(
    owner,
    SourceCollectionPrepared,
    SourceCollectionRetained,
  )
}
