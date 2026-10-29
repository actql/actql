///|
// Only the original Member/geometry/limits entrance, not the Snapshot body.
// Two checked debit sums2H4W remain alongside original access controls.
let program_source_local_snapshot_metadata_peak_bytes : Int64 = program_source_extent_cost(
    @context.source_registration_local_snapshot_inspection_extent(),
  ).unwrap() +
  @execution.preparation_representation_cost(
    program_structure_units(2L, 0L, 4L),
  ).unwrap()

///|
let program_source_local_snapshot_metadata_retained_bytes : Int64 = program_source_extent_cost(
  @context.source_registration_local_snapshot_inspection_retained_extent(),
).unwrap()

///|
/// Fund capture of one original Member and its selected limits on the SAME
/// capacity. O(1) retained metrics do not parse/emit/admit the member or claim
/// body work. This entrance cannot advance Local to its next member.
pub fn[I, P] inspect_program_check_source_local_snapshot(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.phase == SourceLocalGroupsPrepared {
    match reconcile_program_check_source_local_groups(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if !owner.busy && owner.phase == SourceLocalGroupsRetained {
    owner.source_body_quote = None
    owner.phase = SourceLocalSnapshotInitial
  }
  guard !owner.busy &&
    (
      owner.phase == SourceLocalSnapshotInitial ||
      owner.phase == SourceLocalSnapshotObservationFunded
    ) &&
    owner.input is Some(input) &&
    owner.source_registration is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = inspect_program_check_source_local_snapshot_owned(
    owner,
    input,
    @checked.parsed_source_registration_read(original),
  )
  owner.busy = false
  result
}

///|
fn[I, P] inspect_program_check_source_local_snapshot_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  read : @context.SourceRegistrationRead,
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.phase == SourceLocalSnapshotInitial {
    let (r, e) = match
      @resources.preparation_capacity_working_extents(owner.capacity, input) {
      Err(issue) => return Err(Capacity(issue))
      Ok(value) => value
    }
    guard @execution.checked_preparation_add_product(
        r, program_source_local_snapshot_metadata_peak_bytes, 1L,
      )
      is Some(r1) &&
      @execution.checked_preparation_add_product(
        e, program_source_local_snapshot_metadata_peak_bytes, 1L,
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
      Ok(_) => owner.phase = SourceLocalSnapshotObservationFunded
    }
  }
  guard @context.observe_source_registration_local_snapshot_construction(read)
    is Some(_) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  owner.environment_scratch = Some(
    program_source_local_snapshot_metadata_peak_bytes -
    program_source_local_snapshot_metadata_retained_bytes,
  )
  owner.phase = SourceLocalSnapshotInspected
  Ok(())
}

///|
/// Keep the same Member, geometry and original limits. Only the returned
/// access/debit frame retires; no read, body retirement or permission follows.
pub fn[I, P] reconcile_program_check_source_local_snapshot_inspection(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  reconcile_program_check_environment_scratch(
    owner,
    SourceLocalSnapshotInspected,
    SourceLocalSnapshotMetadataRetained,
  )
}
