///|
// Two original collection expansions, quantity/byte conversions and tariffs,
// returned quote pairs/Some, debit sums and bound/result carriers. This fixed
// frame is backed BEFORE input-sized metadata quotation, then kept across a
// failed grow. It is not another quote engine, work allowance or policy cap.
let program_source_snapshot_batch_quote_bytes : Int64 = {
  let expand = @shape.collection_construction_quotation_extent()
  program_source_extent_cost({
    record_headers: 2L * expand.record_headers + 24L,
    reference_slots: 2L * expand.reference_slots + 9L,
    scalar_words: 2L * expand.scalar_words + 58L,
  }).unwrap()
}

///|
// One original receipt, observed step/result/Some and Source failure forwarding.
// No per-Member receipt or current callback is constructed by the body loop.
let program_source_snapshot_batch_driver_bytes : Int64 = {
  let work = @resources.preparation_phase_work_construction_inventory()
  let emitted = @context.source_registration_local_snapshot_work_observation_extent()
  program_source_extent_cost({
    record_headers: work.record_headers + emitted.record_headers + 14L,
    reference_slots: work.reference_slots + emitted.reference_slots + 12L,
    scalar_words: work.scalar_words + emitted.scalar_words + 24L,
  }).unwrap()
}

///|
/// Complete every original Snapshot on the SAME registration/parent. Metadata
/// is retained once before whole-batch growth; one body receipt covers all
/// Members. No Reference receipt is reissued, grow occurs outside active work,
/// and0 members enter their original Declaration successor without body work.
/// Remaining declarations/Context/check still need their own funded entrance.
pub fn[I, P] prepare_program_check_source_local_snapshots(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[
  @context.SourceRegistrationPhase,
  ClientProgramCheckPreparationIssue,
] {
  match inspect_program_check_snapshot_batch_metadata(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if owner.phase == SourceLocalSnapshotBatchComplete {
    return Ok(RegistrationLocal)
  }
  guard !owner.busy &&
    owner.phase == SourceLocalSnapshotBatchRetained &&
    owner.input is Some(input) &&
    owner.source_registration is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_program_check_source_local_snapshots_owned(
    owner,
    input,
    @checked.parsed_source_registration_read(original),
  )
  owner.busy = false
  result
}

///|
// Also used by the focused whitebox boundary case to place its independent
// one-short reservation BETWEEN completed metadata and the body grow. The
// ordinary public driver invokes this same helper without a callback/hook.
fn[I, P] inspect_program_check_snapshot_batch_metadata(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[
  @context.SourceRegistrationPhase,
  ClientProgramCheckPreparationIssue,
] {
  if owner.phase == SourceLocalGroupsPrepared {
    match reconcile_program_check_source_local_groups(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  // A previously selected first-Member prelude remains the SAME input. It is
  // never repeated by this whole-batch entrance.
  if owner.phase == SourceLocalSnapshotReferenceInspected {
    match reconcile_program_check_source_local_snapshot_reference(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if !owner.busy &&
    (
      owner.phase == SourceLocalGroupsRetained ||
      owner.phase == SourceLocalSnapshotReferenceRetained
    ) {
    owner.source_body_quote = None
    owner.phase = SourceLocalSnapshotBatchInitial
  }
  guard !owner.busy &&
    (
      owner.phase == SourceLocalSnapshotBatchInitial ||
      owner.phase == SourceLocalSnapshotBatchQuoted ||
      owner.phase == SourceLocalSnapshotBatchInspected ||
      owner.phase == SourceLocalSnapshotBatchRetained
    ) &&
    owner.input is Some(input) &&
    owner.source_registration is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = inspect_program_check_snapshot_batch_metadata_owned(
    owner,
    input,
    @checked.parsed_source_registration_read(original),
  )
  owner.busy = false
  result
}

///|
fn[I, P] grow_program_check_snapshot_batch(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  added : Int64,
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  let (r, e) = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(r, added, 1L) is Some(r1) &&
    @execution.checked_preparation_add_product(e, added, 1L) is Some(e1) else {
    return Err(Overflow)
  }
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r1, e1) {
    Err(issue) => Err(Capacity(issue))
    Ok(_) => Ok(())
  }
}

///|
fn[I, P] inspect_program_check_snapshot_batch_metadata_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  read : @context.SourceRegistrationRead,
) -> Result[
  @context.SourceRegistrationPhase,
  ClientProgramCheckPreparationIssue,
] {
  if owner.phase == SourceLocalSnapshotBatchInitial {
    if @context.source_registration_local_phase(read)
      is Some(LocalEnvironmentDeclaration) ||
      @context.source_registration_local_phase(read)
      is Some(LocalEnvironmentAssembly) {
      // The original no-Member path already constructed the empty Stage array.
      match current_program_check_preparation(owner) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      owner.phase = SourceLocalSnapshotBatchComplete
      return Ok(RegistrationLocal)
    }
    guard @context.source_registration_local_phase(read)
      is Some(LocalEnvironmentSnapshot) else {
      return Err(WrongPhase)
    }
    match
      grow_program_check_snapshot_batch(
        owner, input, program_source_snapshot_batch_quote_bytes,
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => owner.phase = SourceLocalSnapshotBatchQuoted
    }
  }
  if owner.phase == SourceLocalSnapshotBatchQuoted {
    if owner.source_body_quote is None {
      guard @context.source_registration_local_snapshot_batch_inspection_extent(
          read,
        )
        is Some(peak) &&
        @context.source_registration_local_snapshot_batch_retained_extent(read)
        is Some(held) &&
        program_source_extent_cost(peak) is Some(peak) &&
        program_source_extent_cost(held) is Some(held) else {
        return Err(Overflow)
      }
      guard @execution.checked_preparation_add_product(
          peak, program_source_snapshot_batch_driver_bytes, 1L,
        )
        is Some(peak) else {
        return Err(Overflow)
      }
      owner.source_body_quote = Some((peak, held))
    }
    let (peak, held) = owner.source_body_quote.unwrap()
    match grow_program_check_snapshot_batch(owner, input, peak) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    guard @context.source_registration_local_snapshot_batch_inspection_bound(
        read,
      )
      is Some(bound) else {
      owner.phase = Failed
      return Err(WrongPhase)
    }
    let work = match
      @resources.begin_preparation_phase_work64(
        owner.capacity,
        input,
        @resources.SourceLocalSnapshotBodyInspection,
        bound,
      ) {
      Err(issue) => {
        owner.phase = Failed
        return Err(Work(issue))
      }
      Ok(value) => value
    }
    owner.work = Some(work)
    guard @context.observe_source_registration_local_snapshot_batch_construction(
        read,
      )
      is Some(_) else {
      owner.phase = Failed
      return Err(Overflow)
    }
    // The Member selection loop adds one actual visit per original wrapper.
    let body = @context.source_registration_local_snapshot_batch_body_construction(
      read,
    ).unwrap()
    match finish_program_check_source_work(owner, work, body.inspection_work) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    owner.environment_scratch = Some(peak - held)
    owner.source_body_quote = None
    owner.phase = SourceLocalSnapshotBatchInspected
  }
  if owner.phase == SourceLocalSnapshotBatchInspected {
    // No active work remains when the original parent/current is revisited.
    match reconcile_program_check_snapshot_batch_metadata(owner, input) {
      Err(issue) => return Err(issue)
      Ok(_) => owner.phase = SourceLocalSnapshotBatchRetained
    }
  }
  Ok(RegistrationLocal)
}

///|
fn[I, P] quote_program_check_snapshot_batch_body(
  owner : ClientProgramCheckPreparation[I, P],
  read : @context.SourceRegistrationRead,
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.source_body_quote is None {
    guard @context.source_registration_local_snapshot_batch_body_construction(
        read,
      )
      is Some(inventory) &&
      program_catalog_extent_cost(inventory.peak) is Some(peak) &&
      program_catalog_extent_cost(inventory.retained) is Some(held) else {
      return Err(Overflow)
    }
    guard @execution.checked_preparation_add_product(
        peak, program_source_snapshot_batch_driver_bytes, 1L,
      )
      is Some(peak) else {
      return Err(Overflow)
    }
    owner.source_body_quote = Some((peak, held))
  }
  Ok(())
}

///|
fn[I, P] prepare_program_check_source_local_snapshots_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  read : @context.SourceRegistrationRead,
) -> Result[
  @context.SourceRegistrationPhase,
  ClientProgramCheckPreparationIssue,
] {
  match quote_program_check_snapshot_batch_body(owner, read) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let (peak, held) = owner.source_body_quote.unwrap()
  match grow_program_check_snapshot_batch(owner, input, peak) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard @context.source_registration_local_snapshots_work_bound(read)
    is Some(bound) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  let work = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.SourceLocalSnapshotBody,
      bound.to_int64(),
    ) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(value) => value
  }
  owner.work = Some(work)
  let mut phase = @context.source_registration_phase(read)
  while @context.source_registration_local_phase(read)
        is Some(LocalEnvironmentSnapshot) {
    phase = @context.advance_source_registration(read)
    guard @context.source_registration_local_snapshot_work(read) is Some(spent) else {
      owner.phase = Failed
      return Err(WrongPhase)
    }
    match @resources.spend_preparation_phase_work64(work, spent.to_int64()) {
      Err(issue) => {
        owner.phase = Failed
        return Err(Work(issue))
      }
      Ok(_) => ()
    }
  }
  match @resources.finish_preparation_phase_work64(work) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(_) => owner.work = None
  }
  match phase {
    RegistrationFailed => owner.phase = SourceLocalSnapshotBatchFailed
    RegistrationLocal => {
      guard @context.source_registration_local_phase(read)
        is Some(LocalEnvironmentDeclaration) else {
        owner.phase = Failed
        return Err(WrongPhase)
      }
      owner.environment_scratch = Some(
        peak - held + program_source_snapshot_batch_quote_bytes,
      )
      owner.phase = SourceLocalSnapshotBatchPrepared
    }
    _ => {
      owner.phase = Failed
      return Err(WrongPhase)
    }
  }
  Ok(phase)
}

///|
pub fn[I, P] reconcile_program_check_source_local_snapshots(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  reconcile_program_check_environment_scratch(
    owner,
    SourceLocalSnapshotBatchPrepared,
    SourceLocalSnapshotBatchComplete,
  )
}

///|
// Called only inside the original busy interval. Reentry remains blocked
// through the existing reconciliation/current callback; no state is unlocked
// to invoke another public wrapper or to grow while body work is active.
fn[I, P] reconcile_program_check_snapshot_batch_metadata(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  guard owner.environment_scratch is Some(scratch) else {
    return Err(WrongPhase)
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  if scratch < 0L || scratch >= r || scratch > e {
    return Err(Overflow)
  }
  match
    @resources.reconcile_working_preparation_phase(
      owner.capacity,
      input,
      r - scratch,
      e - scratch,
    ) {
    Err(issue) => Err(Capacity(issue))
    Ok(_) => {
      owner.environment_scratch = None
      Ok(())
    }
  }
}
