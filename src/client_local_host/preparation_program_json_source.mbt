///|
priv enum ProgramJsonPreparationPhase {
  Preflight
  Ready
  Indexed
  RetainedIndex
  Inspected
  Constructed
  RetainedProgram
  Transferred
  Failed
  Retired
} derive(Eq)

///|
/// A domain phase holder over the EXISTING Resource owner. This is not a new
/// allocator, Ledger or cleanup engine. The original backend/input lease must
/// remain live through this complete source/index handoff and later consumers.
struct ClientProgramJsonPreparation[I, P] {
  capacity : @resources.PreparationCapacity[I, P]
  mut input : I?
  mut source : @syntax.ProgramJsonInput?
  mut indexed : @syntax.ParsedProgramInput?
  mut ready : @source.JsonSourceGeometry?
  mut retained_index : @execution.PreparationRepresentationUnits?
  mut structure : @syntax.ProgramConstructorInventory?
  mut structure_quote : (Int64, Int64)?
  mut program : @syntax.Program?
  mut structural_issue : @syntax.SyntaxError?
  mut work : @resources.PreparationPhaseWork64?
  limits : @syntax.Limits
  base_retained : Int64
  base_execution : Int64
  mut busy : Bool
  mut phase : ProgramJsonPreparationPhase
}

///|
pub(all) enum ClientProgramJsonPreparationIssue {
  Capacity(@resources.PreparationCapacityIssue)
  Syntax(@syntax.SyntaxError)
  Source(@syntax.ProgramJsonInputIssue)
  Control(@source.JsonSourcePreflightIssue)
  WrongPhase
  Overflow
  Work(@resources.PreparationWorkIssue)
} derive(Eq, Debug)

///|
/// The existing caller supplies its physical first-prelude before this entry.
/// Add the immutable domain recipe ONCE to the SAME capacity's outside debit,
/// then reserve these new Core roles before their constructors. This function
/// neither selects policy headroom nor creates another reservation/parent.
pub fn[I, P] begin_program_json_preparation(
  capacity : @resources.PreparationCapacity[I, P],
  input : I,
  document : String,
  limits : @syntax.Limits,
  source_path? : String = "<memory>",
) -> Result[
  ClientProgramJsonPreparation[I, P],
  ClientProgramJsonPreparationIssue,
] {
  let (base_retained, base_execution) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(
      base_retained, program_json_initial_control_bytes, 1L,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      base_execution, program_json_initial_control_bytes, 1L,
    )
    is Some(execution) else {
    return Err(Overflow)
  }
  match
    @resources.reserve_working_preparation_phase(
      capacity, input, retained, execution,
    ) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  // The same outside caller already owns capacity on every error return. The
  // original limits can fail before a Source cursor is created; no heavy
  // intermediate is lost or automatically acknowledged as physically closed.
  let source = match
    @syntax.start_program_json_input(document, limits, source_path~) {
    Err(issue) => return Err(Syntax(issue))
    Ok(value) => value
  }
  Ok({
    capacity,
    input: Some(input),
    source: Some(source),
    indexed: None,
    ready: None,
    retained_index: None,
    structure: None,
    structure_quote: None,
    program: None,
    structural_issue: None,
    work: None,
    limits,
    base_retained,
    base_execution,
    busy: false,
    phase: Preflight,
  })
}

///|
pub fn[I, P] advance_program_json_preparation(
  owner : ClientProgramJsonPreparation[I, P],
  quantum : Int,
) -> Result[@source.JsonSourcePreflightPoll, ClientProgramJsonPreparationIssue] {
  if quantum < 1 {
    return Err(Control(@source.JsonSourcePreflightIssue::InvalidQuantum))
  }
  if owner.busy {
    return Err(WrongPhase)
  }
  owner.busy = true
  let current = current_program_json_preparation(owner)
  owner.busy = false
  match current {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if owner.phase == Ready {
    guard owner.source is Some(original) else { return Err(WrongPhase) }
    return match
      @syntax.advance_program_json_input_preflight(original, quantum) {
      Err(issue) => Err(Control(issue))
      Ok(value) => Ok(value)
    }
  }
  guard owner.phase == Preflight && owner.source is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let outcome = match
    @syntax.advance_program_json_input_preflight(original, quantum) {
    Err(issue) => Err(Control(issue))
    Ok(value) => Ok(value)
  }
  match outcome {
    Ok(@source.JsonSourceReady(geometry, ..)) => {
      owner.ready = Some(geometry)
      owner.phase = Ready
    }
    Ok(@source.JsonSourceFailed(_, ..)) | Err(_) => owner.phase = Failed
    _ => ()
  }
  owner.busy = false
  outcome
}

///|
/// Failed quote/grow retains the SAME source/ready report and outside debit.
/// There is no finally retirement or replay of the parser/Unicode preflight.
pub fn[I, P] finish_program_json_preparation(
  owner : ClientProgramJsonPreparation[I, P],
) -> Result[Unit, ClientProgramJsonPreparationIssue] {
  if owner.busy {
    return Err(WrongPhase)
  }
  if owner.phase == Ready {
    match finish_program_json_preparation_index_phase(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  } else if owner.phase != Indexed {
    return Err(WrongPhase)
  }
  // This frame never owns the parser/Source AST or its temporary aliases.
  // The complete index constructor frame above has returned before disposal.
  reconcile_program_json_preparation_index(owner)
}

///|
fn[I, P] finish_program_json_preparation_index_phase(
  owner : ClientProgramJsonPreparation[I, P],
) -> Result[Unit, ClientProgramJsonPreparationIssue] {
  guard !owner.busy &&
    owner.phase == Ready &&
    owner.source is Some(original) &&
    owner.input is Some(input) &&
    owner.ready is Some(geometry) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = finish_program_json_preparation_owned(
    owner, input, original, geometry,
  )
  owner.busy = false
  result
}

///|
fn[I, P] finish_program_json_preparation_owned(
  owner : ClientProgramJsonPreparation[I, P],
  input : I,
  original : @syntax.ProgramJsonInput,
  geometry : @source.JsonSourceGeometry,
) -> Result[Unit, ClientProgramJsonPreparationIssue] {
  guard program_json_source_index_quote(geometry, owner.limits)
    is Some((core_retained, core_execution)) &&
    @execution.checked_preparation_add_product(
      owner.base_retained,
      core_retained,
      1L,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      owner.base_execution,
      core_execution,
      1L,
    )
    is Some(execution) else {
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
  match @syntax.finish_program_json_input(original) {
    Err(issue) => {
      owner.phase = Failed
      owner.source = None
      owner.ready = None
      Err(Source(issue))
    }
    Ok(value) => {
      owner.indexed = Some(value)
      owner.source = None
      // Retain the original raw geometry until its indexed dependencies are
      // priced from the actual immutable admission usage, without another walk.
      owner.phase = Indexed
      Ok(())
    }
  }
}

///|
/// One DATA handoff only. The same reservation remains charged and the next
/// real consumer must retain this indexed input until its own borrowers retire.
/// This does not install a fake final body or transfer/close Resource ownership.
pub fn[I, P] take_program_json_preparation_input(
  owner : ClientProgramJsonPreparation[I, P],
) -> Result[@syntax.ParsedProgramInput, ClientProgramJsonPreparationIssue] {
  guard !owner.busy &&
    (owner.phase == Indexed || owner.phase == RetainedIndex) &&
    owner.indexed is Some(value) else {
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
  owner.input = None
  owner.phase = Transferred
  Ok(value)
}

///|
/// Clear only this phase's actual synchronous aliases. Never close the parent
/// reservation or infer a backend input/reader/physical cleanup ACK. After a
/// handoff, the next consumer still owns the original indexed output.
pub fn[I, P] clear_program_json_preparation(
  owner : ClientProgramJsonPreparation[I, P],
) -> Result[Unit, ClientProgramJsonPreparationIssue] {
  if owner.busy {
    return Err(WrongPhase)
  }
  if owner.work is Some(work) {
    match @resources.finish_preparation_phase_work64(work) {
      Err(issue) => return Err(Work(issue))
      Ok(_) => owner.work = None
    }
  }
  if owner.source is Some(source) {
    @syntax.cancel_program_json_input(source)
  }
  owner.source = None
  owner.indexed = None
  owner.ready = None
  owner.retained_index = None
  owner.structure = None
  owner.structure_quote = None
  owner.program = None
  owner.structural_issue = None
  owner.input = None
  // Clearing this controller cannot retire the next consumer's taken DATA.
  // Keep that handoff fact for the original parent's cleanup boundary.
  if owner.phase != Transferred {
    owner.phase = Retired
  }
  Ok(())
}

///|
fn[I, P] current_program_json_preparation(
  owner : ClientProgramJsonPreparation[I, P],
) -> Result[Unit, ClientProgramJsonPreparationIssue] {
  guard owner.input is Some(input) else { return Err(WrongPhase) }
  match
    @resources.check_working_preparation_capacity_current(owner.capacity, input) {
    Err(issue) => Err(Capacity(issue))
    Ok(_) => Ok(())
  }
}

///|
/// Called only after the private index constructor frame returned. Its original
/// synchronous parser/index stack has unwound and no Source AST escaped that
/// call. The SAME immutable index, spans/Strings, ready DATA and outside
/// dependencies stay held. Only their retired constructor peak is returned.
/// This does not release physical input/VM backing or a parent reservation.
fn[I, P] reconcile_program_json_preparation_index(
  owner : ClientProgramJsonPreparation[I, P],
) -> Result[Unit, ClientProgramJsonPreparationIssue] {
  guard !owner.busy &&
    owner.phase == Indexed &&
    owner.indexed is Some(indexed) &&
    (owner.ready is Some(_) || owner.retained_index is Some(_)) &&
    owner.input is Some(input) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = reconcile_program_json_preparation_index_owned(
    owner,
    input,
    indexed,
    owner.ready,
  )
  owner.busy = false
  result
}

///|
fn[I, P] reconcile_program_json_preparation_index_owned(
  owner : ClientProgramJsonPreparation[I, P],
  input : I,
  indexed : @syntax.ParsedProgramInput,
  geometry : @source.JsonSourceGeometry?,
) -> Result[Unit, ClientProgramJsonPreparationIssue] {
  let units = match owner.retained_index {
    Some(original) => original
    None => {
      guard geometry is Some(geometry) else { return Err(WrongPhase) }
      guard program_json_retained_index_units(indexed, geometry) is Some(value) else {
        return Err(Overflow)
      }
      owner.retained_index = Some(value)
      value
    }
  }
  guard @execution.preparation_representation_cost(units) is Some(core) &&
    @execution.checked_preparation_add_product(owner.base_retained, core, 1L)
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      core, program_json_quote_control_bytes, 1L,
    )
    is Some(execution_core) &&
    @execution.checked_preparation_add_product(
      owner.base_execution,
      execution_core,
      1L,
    )
    is Some(execution) else {
    return Err(Overflow)
  }
  // The existing engine refreshes currentness once and permits proven disposal
  // during stopping. There is no separate current callback or no-op resize.
  match
    @resources.reconcile_working_preparation_phase(
      owner.capacity,
      input,
      retained,
      execution,
    ) {
    Err(issue) => Err(Capacity(issue))
    Ok(_) => {
      owner.phase = RetainedIndex
      Ok(())
    }
  }
}
