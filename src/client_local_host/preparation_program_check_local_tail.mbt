///|
// Same scalar quote/byte-fold carriers as the Snapshot entrance. The Local
// metadata constructor itself has a separate input-derived overlap below.
let program_source_local_tail_quote_bytes : Int64 = program_source_snapshot_batch_quote_bytes

///|
// One body receipt, original Local observation/Result and Source forwarding.
// No receipt, grow/current call or work allowance is reissued per Stage.
let program_source_local_tail_driver_bytes : Int64 = {
  let receipt = @resources.preparation_phase_work_construction_inventory()
  let observed = @context.source_registration_local_tail_work_observation_extent()
  program_source_extent_cost({
    record_headers: receipt.record_headers + observed.record_headers + 14L,
    reference_slots: receipt.reference_slots + observed.reference_slots + 12L,
    scalar_words: receipt.scalar_words + observed.scalar_words + 24L,
  }).unwrap()
}

///|
// One completed metadata observation on the original Source read. Factoring
// this step lets the caller retain the SAME quote across a body grow refusal;
// there is no callback, new input or second metadata traversal on retry.
fn[I, P] inspect_program_check_local_tail_metadata(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.phase == SourceLocalSnapshotBatchPrepared {
    match reconcile_program_check_source_local_snapshots(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if !owner.busy && owner.phase == SourceLocalSnapshotBatchComplete {
    owner.source_body_quote = None
    owner.phase = SourceLocalTailInitial
  }
  guard !owner.busy &&
    (
      owner.phase == SourceLocalTailInitial ||
      owner.phase == SourceLocalTailQuoted ||
      owner.phase == SourceLocalTailInspected ||
      owner.phase == SourceLocalTailRetained
    ) &&
    owner.input is Some(input) &&
    owner.source_registration is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = inspect_program_check_local_tail_metadata_owned(
    owner,
    input,
    @checked.parsed_source_registration_read(original),
  )
  owner.busy = false
  result
}

///|
fn[I, P] inspect_program_check_local_tail_metadata_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  read : @context.SourceRegistrationRead,
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.phase == SourceLocalTailInitial {
    match
      grow_program_check_source_body(
        owner, input, program_source_local_tail_quote_bytes,
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => owner.phase = SourceLocalTailQuoted
    }
  }
  if owner.phase == SourceLocalTailQuoted {
    if owner.source_body_quote is None {
      guard @context.source_registration_local_tail_inspection_extent(read)
        is Some(peak) &&
        program_source_extent_cost(peak) is Some(peak) &&
        program_source_extent_cost(
          @context.source_registration_local_tail_inspection_retained_extent(),
        )
        is Some(held) &&
        @execution.checked_preparation_add_product(
          peak, program_source_local_tail_driver_bytes, 1L,
        )
        is Some(peak) else {
        return Err(Overflow)
      }
      owner.source_body_quote = Some((peak, held))
    }
    let (peak, held) = owner.source_body_quote.unwrap()
    match grow_program_check_source_body(owner, input, peak) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    guard @context.source_registration_local_tail_inspection_bound(read)
      is Some(bound) else {
      owner.phase = Failed
      return Err(WrongPhase)
    }
    let work = match
      @resources.begin_preparation_phase_work64(
        owner.capacity,
        input,
        @resources.SourceLocalTailInspection,
        bound,
      ) {
      Err(issue) => {
        owner.phase = Failed
        return Err(Work(issue))
      }
      Ok(value) => value
    }
    owner.work = Some(work)
    guard @context.observe_source_registration_local_tail_construction(read)
      is Some(inventory) else {
      // The constructor failed without a completed usage. Keep the active
      // receipt and complete peak until the original clear, not a zero debit.
      owner.phase = Failed
      return Err(Overflow)
    }
    match
      finish_program_check_source_work(owner, work, inventory.inspection_work) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    owner.environment_scratch = Some(peak - held)
    owner.source_body_quote = None
    owner.phase = SourceLocalTailInspected
  }
  if owner.phase == SourceLocalTailInspected {
    match reconcile_program_check_source_body_metadata(owner, input) {
      Err(issue) => return Err(issue)
      Ok(_) => owner.phase = SourceLocalTailRetained
    }
  }
  Ok(())
}

///|
fn[I, P] quote_program_check_local_tail_body(
  owner : ClientProgramCheckPreparation[I, P],
  read : @context.SourceRegistrationRead,
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.source_body_quote is None {
    guard @context.source_registration_local_tail_construction(read)
      is Some(inventory) &&
      program_catalog_extent_cost(inventory.peak) is Some(peak) &&
      program_catalog_extent_cost(inventory.retained) is Some(held) &&
      @execution.checked_preparation_add_product(
        peak, program_source_local_tail_driver_bytes, 1L,
      )
      is Some(peak) else {
      return Err(Overflow)
    }
    owner.source_body_quote = Some((peak, held))
  }
  Ok(())
}

///|
/// Finish the original declarations, schema/score reconciliation and assembly
/// under one Request parent/work receipt. Context/identity/check are separate
/// successors; this does not consume the completed registry or issue a Plan.
pub fn[I, P] prepare_program_check_source_local_tail(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[
  @context.SourceRegistrationPhase,
  ClientProgramCheckPreparationIssue,
] {
  match inspect_program_check_local_tail_metadata(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard !owner.busy &&
    owner.phase == SourceLocalTailRetained &&
    owner.input is Some(input) &&
    owner.source_registration is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_program_check_source_local_tail_owned(
    owner,
    input,
    @checked.parsed_source_registration_read(original),
  )
  owner.busy = false
  result
}

///|
fn[I, P] prepare_program_check_source_local_tail_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  read : @context.SourceRegistrationRead,
) -> Result[
  @context.SourceRegistrationPhase,
  ClientProgramCheckPreparationIssue,
] {
  match quote_program_check_local_tail_body(owner, read) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let (peak, held) = owner.source_body_quote.unwrap()
  match grow_program_check_source_body(owner, input, peak) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard @context.source_registration_local_tail_work_bound(read) is Some(bound) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  let work = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.SourceLocalTailBody,
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
  while phase == RegistrationLocal {
    phase = @context.advance_source_registration(read)
    guard @context.source_registration_local_tail_work(read) is Some(spent) else {
      // A nested failure has no Usage total. Earlier successful debits remain
      // on this exact receipt; only clear may finish it after unwinding.
      owner.phase = SourceLocalTailFailed
      return if phase == RegistrationFailed {
        Ok(phase)
      } else {
        Err(WrongPhase)
      }
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
  if phase == RegistrationFailed {
    owner.phase = SourceLocalTailFailed
  } else if phase == RegistrationComplete {
    owner.environment_scratch = Some(
      peak - held + program_source_local_tail_quote_bytes,
    )
    owner.phase = SourceLocalTailPrepared
  } else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  Ok(phase)
}

///|
pub fn[I, P] reconcile_program_check_source_local_tail(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  reconcile_program_check_environment_scratch(
    owner,
    SourceLocalTailPrepared,
    SourceLocalTailComplete,
  )
}
