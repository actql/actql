///|
let program_topology_local_body_bytes : Int64 = program_source_extent_cost(
  @stage_results.local_program_read_reconciled_input_construction_extent(),
).unwrap()

///|
let program_topology_local_retained_bytes : Int64 = program_source_extent_cost(
  @stage_results.local_program_read_reconciled_input_retained_extent(),
).unwrap()

///|
let program_topology_work_construction_bytes : Int64 = {
  let v = @resources.preparation_phase_work_continuation64_construction_inventory()
  program_source_extent_cost({
    record_headers: v.record_headers,
    reference_slots: v.reference_slots,
    scalar_words: v.scalar_words,
  }).unwrap()
}

///|
let program_topology_work_retained_bytes : Int64 = {
  let v = @resources.preparation_phase_work_continuation64_retained_inventory()
  program_source_extent_cost({
    record_headers: v.record_headers,
    reference_slots: v.reference_slots,
    scalar_words: v.scalar_words,
  }).unwrap()
}

///|
// Same original resize/current/spend/return driver, excluding its separately
// priced receipt. Additional work-bound and selected-read Some2H1R2W.
let program_topology_local_driver_bytes : Int64 = {
  let v = @resources.preparation_phase_work_construction_inventory()
  program_context_input_driver_bytes -
  program_source_extent_cost({
    record_headers: v.record_headers,
    reference_slots: v.reference_slots,
    scalar_words: v.scalar_words,
  }).unwrap() +
  program_source_extent_cost({
    record_headers: 2L,
    reference_slots: 1L,
    scalar_words: 2L,
  }).unwrap()
}

///|
/// Original Context always supplies its already reconciled Local environment.
/// This runs only that constructor, retaining the SAME phase-work receipt for
/// subsequent topology bodies. Imports/typing/Result bodies require their own
/// later backing and are never executed under this entrance's small inventory.
pub fn[I, P] prepare_program_check_source_topology_locals(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[
  @stage_results.LocalProgramReadPhase,
  ClientProgramCheckPreparationIssue,
] {
  if owner.phase == SourceTopologyEntryPrepared {
    match reconcile_program_check_source_topology_entry(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  guard !owner.busy &&
    (
      owner.phase == SourceTopologyEntryComplete ||
      owner.phase == SourceTopologyBodyInitial ||
      owner.phase == SourceTopologyBodyRetained
    ) &&
    owner.input is Some(input) &&
    owner.source_registration is Some(original) &&
    @checked.parsed_source_context_input(original) is Some(Ok(context)) &&
    @context.sourceview_context_topology_read(context) is Some(read) &&
    @stage_results.local_program_read_phase(read) == @stage_results.LocalInputs else {
    return Err(WrongPhase)
  }
  if owner.phase != SourceTopologyBodyInitial {
    owner.source_body_quote = None
    owner.phase = SourceTopologyBodyInitial
  }
  owner.busy = true
  let result = prepare_program_check_source_topology_locals_owned(
    owner, input, read,
  )
  owner.busy = false
  result
}

///|
fn[I, P] prepare_program_check_source_topology_locals_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  read : @stage_results.LocalProgramRead,
) -> Result[
  @stage_results.LocalProgramReadPhase,
  ClientProgramCheckPreparationIssue,
] {
  guard @stage_results.local_program_read_stage_index(read) is Some(position) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  if owner.source_body_quote is None {
    let first = owner.topology_work is None
    owner.source_body_quote = Some(
      (
        program_topology_local_body_bytes +
        program_topology_local_driver_bytes +
        (if first { program_topology_work_construction_bytes } else { 0L }),
        // Only the zero-owned-usage record1H3W remains from this selection.
        program_topology_local_retained_bytes +
        (if first { program_topology_work_retained_bytes } else { 0L }),
      ),
    )
  }
  let (peak, held) = owner.source_body_quote.unwrap()
  match grow_program_check_source_body(owner, input, peak) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // The original resize/current callback can synchronously move or retire
  // this same read. Recheck only phase/position before selecting a callee;
  // no second external current observation or semantic work is performed.
  guard @stage_results.local_program_read_phase(read) ==
    @stage_results.LocalInputs &&
    @stage_results.local_program_read_stage_index(read) is Some(current) &&
    current == position else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  let work = match owner.topology_work {
    Some(work) =>
      match @resources.resume_preparation_phase_work_continuation64(work) {
        Err(issue) => {
          owner.phase = Failed
          return Err(Work(issue))
        }
        Ok(_) => work
      }
    None => {
      guard @stage_results.local_program_read_remaining_work(read)
        is Some(bound) &&
        @stage_results.local_program_read_owned_work(read) is Some(prior) else {
        owner.phase = Failed
        return Err(WrongPhase)
      }
      let work = match
        @resources.begin_preparation_phase_work_continuation64(
          owner.capacity,
          input,
          @resources.SourceTopologyBody,
          bound.to_int64(),
        ) {
        Err(issue) => {
          owner.phase = Failed
          return Err(Work(issue))
        }
        Ok(work) => work
      }
      owner.topology_work = Some(work)
      owner.topology_spent = prior.to_int64()
      work
    }
  }
  let phase = @stage_results.advance_local_program_read(read)
  if phase == @stage_results.Failed {
    // The original failed body has no complete Usage. Do not invent zero,
    // return/refill this receipt or reconcile its peak before actual cleanup.
    owner.phase = SourceTopologyBodyFailed
    return Ok(phase)
  }
  guard phase == @stage_results.Imports &&
    @stage_results.local_program_read_owned_work(read) is Some(spent) &&
    spent.to_int64() >= owner.topology_spent else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  match
    @resources.spend_preparation_phase_work_continuation64(
      work,
      spent.to_int64() - owner.topology_spent,
    ) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(_) => owner.topology_spent = spent.to_int64()
  }
  match @resources.return_preparation_phase_work_continuation64(work) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(_) => ()
  }
  owner.environment_scratch = Some(peak - held)
  owner.phase = SourceTopologyBodyReturned
  Ok(phase)
}

///|
/// Retire only returned constructor scratch. The SAME work receipt remains
/// pending, preserving consumed work and blocking check/transfer/publication.
pub fn[I, P] reconcile_program_check_source_topology_locals(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  reconcile_program_check_environment_scratch(
    owner,
    SourceTopologyBodyReturned,
    SourceTopologyBodyRetained,
  )
}
