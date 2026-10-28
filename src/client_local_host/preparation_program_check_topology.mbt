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
// Fixed call-expanded metadata controls. Existing pre232/89/491 is below
// the Source key/ranking path: common pipeline fold93/54/197 plus max of
// key221/82/473 and ranking229/76/498, Stage observation8/6/16 and original
// conversion/driver9/0/21. Two compound original-position getters replace
// scalar getters with extra2H2R2W. The evidence/Stage construction quotes now
// each retain their original replaced-domain extent (+2R). These are control
// fields, never another input body or allowance.
let program_topology_quotation_bytes : Int64 = program_source_extent_cost({
  record_headers: 341L,
  reference_slots: 146L,
  scalar_words: 734L,
}).unwrap()

///|
// Actual retained Source observation122/75/221, original conversion7/0/17
// and added same-meter observed-work carriers4/2/8. The new post-constructor
// original-position tuple/Some adds2H1R3W. Fields/keys/maps remain
// input-derived in their domain inventories, outside this fixed call frame.
let program_topology_retained_observation_bytes : Int64 = program_source_extent_cost({
    record_headers: 135L,
    reference_slots: 78L,
    scalar_words: 249L,
  },
).unwrap()

///|
fn topology_phase_supported(
  phase : @stage_results.LocalProgramReadPhase,
) -> Bool {
  match phase {
    LocalInputs
    | Imports
    | InputRegistration
    | Pipeline
    | PipelineCarriers
    | PipelineKeys
    | PipelineRankings
    | PipelineCore
    | PipelineCoreInputs
    | PipelineCoreParameters => true
    _ => false
  }
}

///|
fn[I, P] topology_quote_still_original(
  owner : ClientProgramCheckPreparation[I, P],
  read : @stage_results.LocalProgramRead,
) -> Bool {
  @stage_results.local_program_read_phase(read) == owner.topology_quoted_phase &&
  @stage_results.local_program_read_constructor_position(read)
  is Some((stage, position)) &&
  stage == owner.topology_quoted_stage &&
  position == owner.topology_quoted_constructor
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
      @stage_results.local_program_read_constructor_position(read)
      is Some((stage, position)) else {
      return Err(WrongPhase)
    }
    owner.source_body_quote = None
    owner.topology_quoted_phase = phase
    owner.topology_quoted_stage = stage
    owner.topology_quoted_constructor = position
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
  // Returned work can span quantity observation and the later capacity grow.
  // Resume/return are internal original-state transitions, not current/I/O.
  let inspect_work = owner.topology_quoted_phase == @stage_results.PipelineKeys ||
    owner.topology_quoted_phase == @stage_results.PipelineRankings
  if inspect_work {
    guard owner.topology_work is Some(work) else { return Err(WrongPhase) }
    match @resources.resume_preparation_phase_work_continuation64(work) {
      Err(issue) => {
        owner.phase = Failed
        return Err(Work(issue))
      }
      Ok(_) => ()
    }
  }
  guard @stage_results.local_program_read_step_construction(read) is Some(q) &&
    program_topology_extent_cost(q.peak, q.peak_utf16_units) is Some(body) &&
    program_topology_extent_cost(q.replaced, 0L) is Some(replaced) &&
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
  if inspect_work {
    match charge_program_topology_observed_work(owner, read) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    match
      @resources.return_preparation_phase_work_continuation64(
        owner.topology_work.unwrap(),
      ) {
      Err(issue) => {
        owner.phase = Failed
        return Err(Work(issue))
      }
      Ok(_) => ()
    }
  }
  // Retained quantity is still unknown. Keep the whole peak until the original
  // constructor returns and its own actual retained buffers are observed.
  let peak = Int64::max(peak, program_topology_quotation_bytes)
  owner.topology_replaced_bytes = replaced
  owner.source_body_quote = Some((peak, peak))
  owner.environment_scratch = None
  owner.phase = SourceTopologyBodyQuoted
  Ok(())
}

///|
/// Advance exactly the next backed original constructor. The SAME read and
/// work receipt span Local selection, Result imports and input registration;
/// original keys/rankings and CoreInputs continue on that SAME receipt. Later
/// core stages, Result and Context bodies still need their original recipes.
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
      guard @stage_results.local_program_read_work_bound(read) is Some(bound) &&
        @stage_results.local_program_read_owned_work(read) is Some(prior) else {
        owner.phase = Failed
        return Err(WrongPhase)
      }
      let work = match
        @resources.begin_preparation_phase_work_continuation64(
          owner.capacity,
          input,
          @resources.SourceTopologyBody,
          bound,
        ) {
        Err(issue) => {
          owner.phase = Failed
          return Err(Work(issue))
        }
        Ok(work) => work
      }
      owner.topology_work = Some(work)
      owner.topology_observed_work = prior
      work
    }
  }
  let previous = owner.topology_quoted_phase
  let phase = @stage_results.advance_local_program_read(read)
  if phase == @stage_results.Failed {
    // Only a retained original consumed-work fact can debit failed work. The
    // input read shares its Budget with nested Carrier/Contract; other failed
    // domains remain unknown, and no successful Usage/empty fact is invented.
    if @stage_results.local_program_read_owned_work(read) is Some(observed) {
      if observed < owner.topology_observed_work {
        owner.phase = Failed
        return Err(WrongPhase)
      }
      match
        @resources.spend_preparation_phase_work_continuation64(
          work,
          observed - owner.topology_observed_work,
        ) {
        Err(issue) => {
          owner.phase = Failed
          return Err(Work(issue))
        }
        Ok(_) => owner.topology_observed_work = observed
      }
      match @resources.return_preparation_phase_work_continuation64(work) {
        Err(issue) => {
          owner.phase = Failed
          return Err(Work(issue))
        }
        Ok(_) => ()
      }
    }
    // The complete construction peak remains backed until actual clear.
    owner.phase = SourceTopologyBodyFailed
    return Ok(phase)
  }
  let expected = match previous {
    LocalInputs => @stage_results.Imports
    Imports => @stage_results.InputRegistration
    InputRegistration => @stage_results.Pipeline
    Pipeline => @stage_results.PipelineCarriers
    PipelineCarriers => @stage_results.PipelineKeys
    PipelineKeys => @stage_results.PipelineRankings
    PipelineRankings => @stage_results.PipelineCore
    PipelineCore => @stage_results.PipelineCoreInputs
    PipelineCoreInputs | PipelineCoreParameters => phase
    _ => {
      owner.phase = Failed
      return Err(WrongPhase)
    }
  }
  guard @stage_results.local_program_read_constructor_position(read)
    is Some((stage, position)) &&
    stage == owner.topology_quoted_stage &&
    position == owner.topology_quoted_constructor + 1L &&
    phase == expected &&
    (
      previous != @stage_results.PipelineCoreInputs ||
      phase == @stage_results.PipelineCoreInputs ||
      phase == @stage_results.PipelineCoreParameters
    ) &&
    (
      previous != @stage_results.PipelineCoreParameters ||
      phase == @stage_results.PipelineCoreParameters ||
      phase == @stage_results.PipelineCoreImportedEvidence
    ) &&
    @stage_results.local_program_read_owned_work(read) is Some(spent) &&
    spent >= owner.topology_observed_work else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  match
    @resources.spend_preparation_phase_work_continuation64(
      work,
      spent - owner.topology_observed_work,
    ) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(_) => owner.topology_observed_work = spent
  }
  guard @stage_results.local_program_read_step_retained_extent(read, previous)
    is Some(retained) &&
    program_topology_extent_cost(retained.extent, retained.owned_utf16_units)
    is Some(held) &&
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
    @execution.checked_preparation_add_product(
      peak,
      owner.topology_replaced_bytes,
      1L,
    )
    is Some(backed) &&
    held <= backed else {
    owner.phase = Failed
    return Err(Overflow)
  }
  // Retained-buffer observations also belong to the SAME original meter.
  match charge_program_topology_observed_work(owner, read) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match @resources.return_preparation_phase_work_continuation64(work) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(_) => ()
  }
  owner.source_body_quote = Some((peak, held))
  owner.environment_scratch = Some(peak + owner.topology_replaced_bytes - held)
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

///|
fn program_topology_extent_cost(
  extent : @shape.CollectionConstructionExtent,
  text : Int64,
) -> Int64? {
  @execution.preparation_representation_cost({
    record_headers: extent.record_headers,
    reference_slots: extent.reference_slots,
    scalar_words: extent.scalar_words,
    owned_utf16_units: text,
    owned_wire_bytes: 0L,
  })
}

///|
fn[I, P] charge_program_topology_observed_work(
  owner : ClientProgramCheckPreparation[I, P],
  read : @stage_results.LocalProgramRead,
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  guard owner.topology_work is Some(work) &&
    @stage_results.local_program_read_owned_work(read) is Some(observed) &&
    observed >= owner.topology_observed_work else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  match
    @resources.spend_preparation_phase_work_continuation64(
      work,
      observed - owner.topology_observed_work,
    ) {
    Err(issue) => {
      owner.phase = Failed
      Err(Work(issue))
    }
    Ok(_) => {
      owner.topology_observed_work = observed
      Ok(())
    }
  }
}
