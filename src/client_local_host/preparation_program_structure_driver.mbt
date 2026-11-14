///|
/// Continue the SAME original index/capacity into the ordinary Program
/// constructor. Observation and its original work receipt unwind before grow.
/// Failed grow retains the exact inventory for retry, never replays inspection.
/// This does not perform semantic checking, create a final body or close a
/// parent. Backend input/path/physical backing remain with their actual owner.
pub fn[I, P] construct_program_json_preparation(
  owner : ClientProgramJsonPreparation[I, P],
) -> Result[Unit, ClientProgramJsonPreparationIssue] {
  guard !owner.busy &&
    (owner.phase == RetainedIndex || owner.phase == Inspected) &&
    owner.input is Some(input) &&
    owner.indexed is Some(indexed) &&
    owner.retained_index is Some(index_units) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = construct_program_json_preparation_owned(
    owner, input, indexed, index_units,
  )
  owner.busy = false
  result
}

///|
fn[I, P] construct_program_json_preparation_owned(
  owner : ClientProgramJsonPreparation[I, P],
  input : I,
  indexed : @syntax.ParsedProgramInput,
  index_units : @execution.PreparationRepresentationUnits,
) -> Result[Unit, ClientProgramJsonPreparationIssue] {
  if owner.phase == RetainedIndex {
    // The immutable quote packet was funded at the original Source entry.
    // Reserve the observer's actual fixed controls BEFORE reading the index.
    guard program_structure_observation_quote(owner, index_units)
      is Some((retained, execution)) else {
      return Err(Overflow)
    }
    match
      @resources.reserve_working_preparation_phase(
        owner.capacity,
        input,
        retained,
        execution,
      ) {
      Err(issue) => return Err(Capacity(issue))
      Ok(_) => ()
    }
    let maximum = @syntax.program_constructor_inspection_work_bound(indexed)
    let work = match
      @resources.begin_preparation_phase_work64(
        owner.capacity,
        input,
        @resources.ProgramStructure,
        maximum,
      ) {
      Err(issue) => return Err(Work(issue))
      Ok(value) => value
    }
    owner.work = Some(work)
    let (observed, spent) = @syntax.observe_program_constructor_inventory(
      @syntax.program_input_cursor(indexed),
      maximum,
    )
    // Keep the actual charged work even on failed observation; the maximum
    // is never substituted for performed work or used to classify syntax.
    let charge = @resources.spend_preparation_phase_work64(work, spent)
    match @resources.finish_preparation_phase_work64(work) {
      Err(issue) => return Err(Work(issue))
      Ok(_) => owner.work = None
    }
    match charge {
      Err(issue) => {
        owner.phase = Failed
        return Err(Work(issue))
      }
      Ok(_) => ()
    }
    guard observed is Some(inventory) else {
      owner.phase = Failed
      return Err(Overflow)
    }
    owner.structure = Some(inventory)
    owner.phase = Inspected
  }
  guard owner.structure is Some(inventory) else { return Err(WrongPhase) }
  let quote = match owner.structure_quote {
    Some(original) => original
    None => {
      guard program_structure_construction_quote(owner, index_units, inventory)
        is Some(value) else {
        return Err(Overflow)
      }
      owner.structure_quote = Some(value)
      value
    }
  }
  let (retained, execution) = quote
  match
    @resources.reserve_working_preparation_phase(
      owner.capacity,
      input,
      retained,
      execution,
    ) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  // This is the original full envelope decoder and its SAME stage policy.
  // It still issues the original first typed structural refusal.
  match @syntax.finish_program_input(indexed) {
    Err(issue) => {
      // Keep this exact original failure beside its admitted index. Reporting
      // borrows it; no decoder or successful checker outcome is reissued.
      owner.structural_issue = Some(issue)
      owner.phase = Failed
      Err(Syntax(issue))
    }
    Ok(program) => {
      owner.program = Some(program)
      owner.phase = Constructed
      Ok(())
    }
  }
}

///|
fn[I, P] program_structure_observation_quote(
  owner : ClientProgramJsonPreparation[I, P],
  index_units : @execution.PreparationRepresentationUnits,
) -> (Int64, Int64)? {
  guard @execution.compose_preparation_representation([
      index_units,
      program_structure_inspection_units(),
    ])
    is Some(units) else {
    return None
  }
  program_structure_phase_quote(owner, units, units)
}

///|
fn[I, P] program_structure_construction_quote(
  owner : ClientProgramJsonPreparation[I, P],
  index_units : @execution.PreparationRepresentationUnits,
  inventory : @syntax.ProgramConstructorInventory,
) -> (Int64, Int64)? {
  let depth = @decode.admission_usage(
      @syntax.program_input_cursor(owner.indexed.unwrap()),
    ).depth
  guard program_structure_generic_inventories(inventory, depth) is Some(program) &&
    @execution.compose_preparation_representation([
      index_units,
      program_structure_inspection_units(),
      program.retained,
    ])
    is Some(retained) &&
    @execution.compose_preparation_representation([
      index_units,
      program_structure_inspection_units(),
      program.containers_peak,
      program.carriers_peak,
      program.failure_peak,
    ])
    is Some(execution) else {
    return None
  }
  program_structure_phase_quote(owner, retained, execution)
}

///|
fn[I, P] program_structure_phase_quote(
  owner : ClientProgramJsonPreparation[I, P],
  retained : @execution.PreparationRepresentationUnits,
  execution : @execution.PreparationRepresentationUnits,
) -> (Int64, Int64)? {
  guard @execution.preparation_representation_cost(retained) is Some(r) &&
    @execution.preparation_representation_cost(execution) is Some(e) &&
    @execution.checked_preparation_add_product(owner.base_retained, r, 1L)
    is Some(r) &&
    @execution.checked_preparation_add_product(
      e, program_json_quote_control_bytes, 1L,
    )
    is Some(e) &&
    @execution.checked_preparation_add_product(owner.base_execution, e, 1L)
    is Some(e) else {
    return None
  }
  Some((r, e))
}

///|
/// One actual Program DATA handoff. Its source/index and normalized names are
/// retained by the returned body. The SAME reservation remains charged for the
/// complete constructor peak until the next real phase proves disposal; this
/// is not parent release, physical cleanup ACK or a fake completed module.
pub fn[I, P] take_program_json_preparation_program(
  owner : ClientProgramJsonPreparation[I, P],
) -> Result[@syntax.Program, ClientProgramJsonPreparationIssue] {
  guard !owner.busy &&
    (owner.phase == Constructed || owner.phase == RetainedProgram) &&
    owner.program is Some(program) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let current = current_program_json_preparation(owner)
  owner.busy = false
  match current {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  owner.indexed = None
  owner.ready = None
  owner.retained_index = None
  owner.structure = None
  owner.structure_quote = None
  owner.program = None
  owner.input = None
  owner.phase = Transferred
  Ok(program)
}
