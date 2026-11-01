///|
// Installed quantities are folded by the existing tariff. The original domain
// quote/current/resize controls remain live across this sequential entry; this
// phase adds no dynamic quote collection or independent reservation.
let program_check_source_entry_bytes : Int64 = {
  let value = @checked.parsed_source_registration_entry_extent()
  @execution.preparation_representation_cost(
    program_structure_units(
      value.record_headers,
      value.reference_slots,
      value.scalar_words,
    ),
  ).unwrap()
}

///|
let program_check_source_retained_bytes : Int64 = {
  let value = @checked.parsed_source_registration_retained_extent()
  @execution.preparation_representation_cost(
    program_structure_units(
      value.record_headers,
      value.reference_slots,
      value.scalar_words,
    ),
  ).unwrap()
}

///|
/// Add only the next original entry on the SAME capacity. Source/declarations
/// are an already-backed prior dependency, not reconstructed by this entry.
/// A failed grow retains this exact Source without consuming the registry.
pub fn[I, P] prepare_program_check_source_registration(
  owner : ClientProgramCheckPreparation[I, P],
  source : @stages.Source,
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.phase == RequestsPrepared {
    match reconcile_program_check_requests(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  guard !owner.busy &&
    (owner.phase == RequestsRetained || owner.phase == SourceRegistrationQuoted) &&
    owner.input is Some(input) &&
    owner.check_registry is Some(original) else {
    return Err(WrongPhase)
  }
  if owner.phase == SourceRegistrationQuoted &&
    !(owner.registration_source is Some(selected) &&
    physical_equal(selected, source)) {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_program_check_source_registration_owned(
    owner, input, original, source,
  )
  owner.busy = false
  result
}

///|
fn[I, P] prepare_program_check_source_registration_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  original : @checked.ParsedCheckRegistry,
  source : @stages.Source,
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.phase == RequestsRetained {
    owner.registration_source = Some(source)
    owner.phase = SourceRegistrationQuoted
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(
      r, program_check_source_entry_bytes, 1L,
    )
    is Some(r1) &&
    @execution.checked_preparation_add_product(
      e, program_check_source_entry_bytes, 1L,
    )
    is Some(e1) else {
    return Err(Overflow)
  }
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r1, e1) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  match @checked.begin_parsed_source_registration(original, source) {
    Err(issue) => {
      owner.phase = Failed
      Err(SourceRegistration(issue))
    }
    Ok(value) => {
      owner.source_registration = Some(value)
      owner.environment_scratch = Some(
        program_check_source_entry_bytes - program_check_source_retained_bytes,
      )
      owner.phase = SourceRegistrationPrepared
      Ok(())
    }
  }
}

///|
/// Only returned synchronous entry scratch retires. All original input/Source,
/// completed Catalog, continuation and the same parent reservation survive.
pub fn[I, P] reconcile_program_check_source_registration(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  reconcile_program_check_environment_scratch(
    owner,
    SourceRegistrationPrepared,
    SourceRegistrationRetained,
  )
}

///|
/// Transfer the original continuation once after the existing current gate.
/// Future read phases and final Context still require their own funded overlap;
/// this take does not complete a check, Plan or physical cleanup.
pub fn[I, P] take_program_check_source_registration(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[
  @checked.ParsedSourceRegistration,
  ClientProgramCheckPreparationIssue,
] {
  guard !owner.busy &&
    (
      owner.phase == SourceRegistrationPrepared ||
      owner.phase == SourceRegistrationRetained ||
      owner.phase == SourceCollectionPrepared ||
      owner.phase == SourceCollectionRetained ||
      owner.phase == SourceCollectionFailed ||
      owner.phase == SourceResolutionPrepared ||
      owner.phase == SourceResolutionRetained ||
      owner.phase == SourceResolutionFailed ||
      owner.phase == SourcePipelinePrepared ||
      owner.phase == SourcePipelineRetained ||
      owner.phase == SourcePipelineFailed ||
      owner.phase == SourceLocalEntryPrepared ||
      owner.phase == SourceLocalEntryRetained ||
      owner.phase == SourceLocalEntryFailed ||
      owner.phase == SourceLocalIndexPrepared ||
      owner.phase == SourceLocalIndexRetained ||
      owner.phase == SourceLocalIndexFailed ||
      owner.phase == SourceLocalGroupsPrepared ||
      owner.phase == SourceLocalGroupsRetained ||
      owner.phase == SourceLocalGroupsFailed ||
      owner.phase == SourceLocalSnapshotInspected ||
      owner.phase == SourceLocalSnapshotMetadataRetained ||
      owner.phase == SourceLocalSnapshotReferenceInspected ||
      owner.phase == SourceLocalSnapshotReferenceRetained ||
      owner.phase == SourceLocalSnapshotBatchInspected ||
      owner.phase == SourceLocalSnapshotBatchRetained ||
      owner.phase == SourceLocalSnapshotBatchPrepared ||
      owner.phase == SourceLocalSnapshotBatchFailed ||
      owner.phase == SourceLocalSnapshotBatchComplete
    ) &&
    owner.source_registration is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let current = current_program_check_preparation(owner)
  owner.busy = false
  match current {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  transfer_program_check_input(owner)
  Ok(original)
}
