///|
// This one prelude observes the first SAME captured Member, not an all-member
// body work session. Later Snapshot construction needs its full backed overlap
// and distinct work before entry; this receipt must never be reissued per row.
// The actual work receipt12H16R18W, two debit sums2H4W, three caller result/error
// carriers3H2R3W and returned scratch Some1H2W overlap the original observer.
let program_source_snapshot_reference_peak_bytes : Int64 = {
  let original = @context.source_registration_local_snapshot_reference_inspection_extent()
  let work = @resources.preparation_phase_work_construction_inventory()
  @execution.preparation_representation_cost(
    program_structure_units(
      original.record_headers + work.record_headers + 6L,
      original.reference_slots + work.reference_slots + 2L,
      original.scalar_words + work.scalar_words + 9L,
    ),
  ).unwrap()
}

///|
let program_source_snapshot_reference_retained_bytes : Int64 = program_source_extent_cost(
  @context.source_registration_local_snapshot_reference_retained_extent(),
).unwrap()

///|
/// Back the SAME original Member's metadata observation and quantity recipe
/// before either executes. No replacement Member/limits/quote/permission enters.
/// A failed grow has observed nothing and may retry on this original parent;
/// a begun work phase is never reset, refunded or issued a second time.
pub fn[I, P] inspect_program_check_source_local_snapshot_reference(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.phase == SourceLocalSnapshotInspected {
    match reconcile_program_check_source_local_snapshot_inspection(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if !owner.busy && owner.phase == SourceLocalSnapshotMetadataRetained {
    owner.phase = SourceLocalSnapshotReferenceInitial
  }
  guard !owner.busy &&
    (
      owner.phase == SourceLocalSnapshotReferenceInitial ||
      owner.phase == SourceLocalSnapshotReferenceObservationFunded
    ) &&
    owner.input is Some(input) &&
    owner.source_registration is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = inspect_program_check_source_local_snapshot_reference_owned(
    owner,
    input,
    @checked.parsed_source_registration_read(original),
  )
  owner.busy = false
  result
}

///|
fn[I, P] inspect_program_check_source_local_snapshot_reference_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  read : @context.SourceRegistrationRead,
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.phase == SourceLocalSnapshotReferenceInitial {
    let (r, e) = match
      @resources.preparation_capacity_working_extents(owner.capacity, input) {
      Err(issue) => return Err(Capacity(issue))
      Ok(value) => value
    }
    guard @execution.checked_preparation_add_product(
        r, program_source_snapshot_reference_peak_bytes, 1L,
      )
      is Some(r1) &&
      @execution.checked_preparation_add_product(
        e, program_source_snapshot_reference_peak_bytes, 1L,
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
      Ok(_) => owner.phase = SourceLocalSnapshotReferenceObservationFunded
    }
  }
  guard @context.source_registration_local_snapshot_reference_inspection_bound(
      read,
    )
    is Some(maximum) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  let work = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.SourceLocalSnapshotReferenceInspection,
      maximum,
    ) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(value) => value
  }
  owner.work = Some(work)
  guard @context.observe_source_registration_local_snapshot_reference_construction(
      read,
    )
    is Some((_, spent)) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  match finish_program_check_source_work(owner, work, spent) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  owner.environment_scratch = Some(
    program_source_snapshot_reference_peak_bytes -
    program_source_snapshot_reference_retained_bytes,
  )
  owner.phase = SourceLocalSnapshotReferenceInspected
  Ok(())
}

///|
/// Retain the exact completed quantity/work Option. Only returned synchronous
/// inspection/work scratch retires; spent work and all older backing survive.
pub fn[I, P] reconcile_program_check_source_local_snapshot_reference(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  reconcile_program_check_environment_scratch(
    owner,
    SourceLocalSnapshotReferenceInspected,
    SourceLocalSnapshotReferenceRetained,
  )
}
