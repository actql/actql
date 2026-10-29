///|
/// Fund observation, retain its immutable quote across failed grows, then bind
/// the original capacity evidence once. The original backend must keep these
/// borrowed arguments immutable and attached to its admitted input.
pub fn[I, P] prepare_program_check_input(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  guard !owner.busy &&
    (owner.phase == BindingInitial || owner.phase == BindingQuoted) &&
    owner.input is Some(input) &&
    owner.arguments is Some(arguments) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_program_check_input_owned(owner, input, arguments)
  owner.busy = false
  result
}

///|
fn[I, P] prepare_program_check_input_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  arguments : ProgramCheckArguments,
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.phase == BindingInitial {
    guard @execution.checked_preparation_add_product(
        program_check_initial_control_bytes, program_check_input_observer_bytes,
        1L,
      )
      is Some(core) &&
      @execution.checked_preparation_add_product(owner.base_retained, core, 1L)
      is Some(r) &&
      @execution.checked_preparation_add_product(owner.base_execution, core, 1L)
      is Some(e) else {
      return Err(Overflow)
    }
    match
      @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
      Err(issue) => return Err(Capacity(issue))
      Ok(_) => ()
    }
    // At most one initial observation and one post-callback comparison. A
    // failed atomic grow returns before that comparison and retains this same
    // quote. Each completed observation closes before the next grow; retries
    // neither refill its named receipt nor rescan the original dimensions.
    let maximum = 1L + @syntax.stage_count(arguments.program).to_int64()
    let work = match
      @resources.begin_preparation_phase_work64(
        owner.capacity,
        input,
        @resources.CapacityInputInspection,
        maximum,
      ) {
      Err(issue) => {
        owner.phase = Failed
        return Err(Work(issue))
      }
      Ok(value) => value
    }
    owner.work = Some(work)
    let (observed, spent) = @context.observe_capacity_input_construction_inventory(
      arguments.program,
      arguments.evidence,
    )
    let charged = @resources.spend_preparation_phase_work64(work, spent)
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
        return Err(Work(issue))
      }
      Ok(_) => ()
    }
    guard observed is Some(inventory) &&
      @shape.collection_construction_extent(inventory) is Some(extent) else {
      owner.phase = Failed
      return Err(Overflow)
    }
    owner.binding_inventory = Some(inventory)
    let holder = @checked.parsed_check_input_retained_control_extent()
    guard @execution.compose_preparation_representation([
        program_structure_units(
          extent.record_headers,
          extent.reference_slots,
          extent.scalar_words,
        ),
        program_structure_units(
          holder.record_headers,
          holder.reference_slots,
          holder.scalar_words,
        ),
      ])
      is Some(units) &&
      @execution.preparation_representation_cost(units) is Some(bytes) &&
      @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r1) &&
      @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e1) else {
      owner.phase = Failed
      return Err(Overflow)
    }
    // Original header count is retained by Program construction. These new
    // input-scaled arrays/records coexist with the actual binder; borrowed
    // declaration text/index stays with its existing owner. Fixed controls
    // remain trusted Host overhead, not another per-wrapper census.
    let extra = if owner.effect_limits is Some(_) {
      let n = @syntax.program_preparation_data(arguments.program).effect_members.to_int64()
      let stages = @syntax.stage_count(arguments.program).to_int64()
      let inventory : @shape.CollectionConstructionInventory = {
        records: 2L * n,
        record_references: 16L * n,
        record_words: 2L * n,
        reference_arrays: stages + 1L,
        reference_items: 2L * n + stages,
        scalar_arrays: 0L,
        scalar_items: 0L,
        maps: 0L,
        map_entries: 0L,
      }
      guard @shape.collection_construction_extent(inventory) is Some(header) &&
        @execution.preparation_representation_cost(
          program_structure_units(
            header.record_headers,
            header.reference_slots,
            header.scalar_words,
          ),
        )
        is Some(bytes) else {
        owner.phase = Failed
        return Err(Overflow)
      }
      bytes
    } else {
      0L
    }
    guard @execution.checked_preparation_add_product(r1, extra, 1L) is Some(r1) &&
      @execution.checked_preparation_add_product(e1, extra, 1L) is Some(e1) else {
      owner.phase = Failed
      return Err(Overflow)
    }
    owner.binding_quote = Some((r1, e1))
    owner.phase = BindingQuoted
  }
  guard owner.binding_inventory is Some(inventory) &&
    owner.binding_quote is Some((r, e)) &&
    owner.work is None else {
    return Err(WrongPhase)
  }
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  let work = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.CapacityInputRecheck,
      1L + @syntax.stage_count(arguments.program).to_int64(),
    ) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(value) => value
  }
  owner.work = Some(work)
  let (current, spent) = @context.observe_capacity_input_construction_inventory(
    arguments.program,
    arguments.evidence,
  )
  let charged = @resources.spend_preparation_phase_work64(work, spent)
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
      return Err(Work(issue))
    }
    Ok(_) => ()
  }
  if current != Some(inventory) {
    owner.phase = Failed
    return Err(ChangedInputs)
  }
  let maximum = Int::max(0, arguments.limits.compilation.work).to_int64()
  let receipt = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.CapacityInputBinding,
      maximum,
    ) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(value) => value
  }
  owner.work = Some(receipt)
  let (result, spent) = match owner.effect_limits {
    None => {
      let (outcome, work) = @checked.observe_parsed_check_input_preparation(
        arguments.program,
        arguments.environment,
        arguments.supplied,
        arguments.evidence,
        arguments.limits,
        source_catalog=arguments.source_catalog,
        source_preparation=arguments.source_preparation,
      )
      (
        outcome.map_err(issue => {
          ClientProgramCheckPreparationIssue::Check(issue)
        }),
        work,
      )
    }
    Some(limits) => {
      let (outcome, work) = @checked.observe_prepare_effect_computation_input(
        arguments.program,
        arguments.environment,
        arguments.supplied,
        arguments.evidence,
        arguments.limits,
        limits.max_members,
        limits.max_header_work,
        source_catalog=arguments.source_catalog,
        source_preparation=arguments.source_preparation,
      )
      (
        outcome.map_err(issue => {
          ClientProgramCheckPreparationIssue::EffectInput(issue)
        }),
        work,
      )
    }
  }
  if result is Ok(value) {
    owner.check_input = Some(value)
  }
  let charged = @resources.spend_preparation_phase_work64(
    receipt,
    spent.to_int64(),
  )
  match @resources.finish_preparation_phase_work64(receipt) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(_) => owner.work = None
  }
  match charged {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(_) => ()
  }
  match result {
    Err(issue) => {
      owner.phase = Failed
      Err(issue)
    }
    Ok(_) => {
      owner.phase = CheckPrepared
      Ok(())
    }
  }
}

///|
/// DATA handoff only. The original capacity remains charged for all retained
/// backing and binder peak; a later complete semantic phase must fund itself.
pub fn[I, P] take_program_check_input(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[@checked.ParsedCheckInput, ClientProgramCheckPreparationIssue] {
  guard !owner.busy &&
    owner.phase == CheckPrepared &&
    owner.check_input is Some(original) else {
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
