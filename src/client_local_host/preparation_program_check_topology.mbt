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
// Original resize/current/spend/return driver, excluding the separately priced
// receipt. Additional remaining-work and selected-read Some2H1R2W.
let program_topology_body_driver_bytes : Int64 = {
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
// Call-expanded pre-quotation: original domain recipes223H89R470W,
// conversion/tariff6H15W and three checked sums3H6W. No input body is
// included. This returned frame is reused instead of shrink/immediate grow.
let program_topology_quotation_bytes : Int64 = program_source_extent_cost({
  record_headers: 232L,
  reference_slots: 89L,
  scalar_words: 491L,
}).unwrap()

///|
// Original retained observation: Local2H1R4W, imports26H25R50W,
// inputs48H31R95W, conversion/tariff6H15W and held sum1H2W.
// Pre/post quotation calls do not overlap; the caller uses that lifetime.
let program_topology_retained_observation_bytes : Int64 = program_source_extent_cost({
    record_headers: 83L,
    reference_slots: 57L,
    scalar_words: 166L,
  },
).unwrap()

///|
fn topology_phase_supported(
  phase : @stage_results.LocalProgramReadPhase,
) -> Bool {
  match phase {
    LocalInputs | Imports | InputRegistration | Pipeline | PipelineCarriers =>
      true
    _ => false
  }
}

///|
fn[I, P] topology_quote_still_original(
  owner : ClientProgramCheckPreparation[I, P],
  read : @stage_results.LocalProgramRead,
) -> Bool {
  @stage_results.local_program_read_phase(read) == owner.topology_quoted_phase &&
  @stage_results.local_program_read_stage_index(read) is Some(position) &&
  position == owner.topology_quoted_stage
}

///|
// Only the private original read supplies dimensions. The same quote/key
// survives a declined grow; external callbacks cannot move it to another step.
fn[I, P] inspect_program_check_source_topology(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.phase == SourceTopologyEntryPrepared {
    match reconcile_program_check_source_topology_entry(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if owner.phase == SourceTopologyBodyReturned {
    match reconcile_program_check_source_topology(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  guard !owner.busy &&
    (
      owner.phase == SourceTopologyEntryComplete ||
      owner.phase == SourceTopologyBodyRetained ||
      owner.phase == SourceTopologyBodyInspectionInitial ||
      owner.phase == SourceTopologyBodyQuoted
    ) &&
    owner.input is Some(input) &&
    owner.source_registration is Some(original) &&
    @checked.parsed_source_context_input(original) is Some(Ok(context)) &&
    @context.sourceview_context_topology_read(context) is Some(read) else {
    return Err(WrongPhase)
  }
  if owner.phase == SourceTopologyEntryComplete ||
    owner.phase == SourceTopologyBodyRetained {
    let phase = @stage_results.local_program_read_phase(read)
    guard topology_phase_supported(phase) &&
      @stage_results.local_program_read_stage_index(read) is Some(position) else {
      return Err(WrongPhase)
    }
    owner.source_body_quote = None
    owner.topology_quoted_phase = phase
    owner.topology_quoted_stage = position
    owner.phase = SourceTopologyBodyInspectionInitial
  }
  if !topology_quote_still_original(owner, read) {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  if owner.phase == SourceTopologyBodyInspectionInitial {
    owner.busy = true
    let result = inspect_program_check_source_topology_owned(owner, input, read)
    owner.busy = false
    match result {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if !topology_quote_still_original(owner, read) {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  Ok(())
}

///|
fn[I, P] inspect_program_check_source_topology_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  read : @stage_results.LocalProgramRead,
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  match
    grow_program_check_source_body(
      owner, input, program_topology_quotation_bytes,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard topology_quote_still_original(owner, read) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  guard @stage_results.local_program_read_step_construction(read) is Some(q) &&
    program_source_extent_cost(q.peak) is Some(body) &&
    @execution.checked_preparation_add_product(
      body, program_topology_body_driver_bytes, 1L,
    )
    is Some(peak) &&
    @execution.checked_preparation_add_product(
      peak, program_topology_retained_observation_bytes, 1L,
    )
    is Some(peak) &&
    @execution.checked_preparation_add_product(
      peak,
      if owner.topology_work is None {
        program_topology_work_construction_bytes
      } else {
        0L
      },
      1L,
    )
    is Some(peak) else {
    owner.phase = Failed
    return Err(Overflow)
  }
  // Retained quantity is still unknown. Keep the whole peak until the original
  // constructor returns and its own actual retained buffers are observed.
  let peak = Int64::max(peak, program_topology_quotation_bytes)
  owner.source_body_quote = Some((peak, peak))
  owner.environment_scratch = None
  owner.phase = SourceTopologyBodyQuoted
  Ok(())
}

///|
/// Advance exactly the next backed original constructor. The SAME read and
/// work receipt span Local selection, Result imports and input registration;
/// later key/ranking/core typing, Result and Context bodies need their own
/// original recipes first.
pub fn[I, P] advance_program_check_source_topology(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[
  @stage_results.LocalProgramReadPhase,
  ClientProgramCheckPreparationIssue,
] {
  match inspect_program_check_source_topology(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard !owner.busy &&
    owner.phase == SourceTopologyBodyQuoted &&
    owner.input is Some(input) &&
    owner.source_registration is Some(original) &&
    @checked.parsed_source_context_input(original) is Some(Ok(context)) &&
    @context.sourceview_context_topology_read(context) is Some(read) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = advance_program_check_source_topology_owned(owner, input, read)
  owner.busy = false
  result
}

///|
fn[I, P] advance_program_check_source_topology_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  read : @stage_results.LocalProgramRead,
) -> Result[
  @stage_results.LocalProgramReadPhase,
  ClientProgramCheckPreparationIssue,
] {
  let (peak, _) = owner.source_body_quote.unwrap()
  let additional = peak - program_topology_quotation_bytes
  if additional > 0L {
    match grow_program_check_source_body(owner, input, additional) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  guard topology_quote_still_original(owner, read) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  let first = owner.topology_work is None
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
      owner.topology_observed_work = prior.to_int64()
      work
    }
  }
  let previous = owner.topology_quoted_phase
  let phase = @stage_results.advance_local_program_read(read)
  if phase == @stage_results.Failed {
    owner.phase = SourceTopologyBodyFailed
    return Ok(phase)
  }
  let expected = match previous {
    LocalInputs => @stage_results.Imports
    Imports => @stage_results.InputRegistration
    InputRegistration => @stage_results.Pipeline
    Pipeline => @stage_results.PipelineCarriers
    PipelineCarriers => @stage_results.PipelineKeys
    _ => {
      owner.phase = Failed
      return Err(WrongPhase)
    }
  }
  guard phase == expected &&
    @stage_results.local_program_read_owned_work(read) is Some(spent) &&
    spent.to_int64() >= owner.topology_observed_work else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  match
    @resources.spend_preparation_phase_work_continuation64(
      work,
      spent.to_int64() - owner.topology_observed_work,
    ) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(_) => owner.topology_observed_work = spent.to_int64()
  }
  guard @stage_results.local_program_read_step_retained_extent(read, previous)
    is Some(retained) &&
    program_source_extent_cost(retained) is Some(held) &&
    @execution.checked_preparation_add_product(
      held,
      if first {
        program_topology_work_retained_bytes
      } else {
        0L
      },
      1L,
    )
    is Some(held) &&
    held <= peak else {
    owner.phase = Failed
    return Err(Overflow)
  }
  match @resources.return_preparation_phase_work_continuation64(work) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(_) => ()
  }
  owner.source_body_quote = Some((peak, held))
  owner.environment_scratch = Some(peak - held)
  owner.phase = SourceTopologyBodyReturned
  Ok(phase)
}

///|
/// Only returned constructor scratch retires. Work/reader ownership and every
/// previously retained typed body stay with this SAME preparation parent.
pub fn[I, P] reconcile_program_check_source_topology(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  reconcile_program_check_environment_scratch(
    owner,
    SourceTopologyBodyReturned,
    SourceTopologyBodyRetained,
  )
}
