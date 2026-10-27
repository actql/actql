///|
priv enum ParameterBindingPreparationPhase {
  BindingInitial
  BindingHeaderQuoted
  BindingHeaderPrepared
  BindingInventoryQuoted
  BindingInventoryPrepared
  BindingSteps
  BindingStepQuoted
  BindingRetained
  BindingSourceQuoted
  BindingSourcePrepared
  BindingSourceRetained
  BindingFailed
  BindingRetired
} derive(Eq)

///|
/// A constructor continuation over the SAME parent, not a Resource Owner.
/// Source/declarations/limits stay borrowed. Each constructor is funded before
/// entry and retains its original semantic result/facts for later phases.
struct ClientParameterBindingPreparation[I, P] {
  capacity : @resources.PreparationCapacity[I, P]
  mut input : I?
  mut prepared : Result[@parameters.BindingReadInput, @parameters.Issue]?
  mut quote : (Int64, Int64)?
  mut work : @resources.PreparationPhaseWork64?
  mut current : @parameters.BindingReadConstructionFacts?
  mut step : @parameters.BindingReadPhase
  mut body_bytes : Int64
  mut maximum_work : Int64
  mut source_input : @stages.Source?
  mut source : Result[@stages.Source, @stages.Issue]?
  base_retained : Int64
  base_execution : Int64
  depth : Int
  mut busy : Bool
  mut phase : ParameterBindingPreparationPhase
}

///|
pub(all) enum ClientParameterBindingPreparationIssue {
  Capacity(@resources.PreparationCapacityIssue)
  Work(@resources.PreparationWorkIssue)
  WrongPhase
  Overflow
} derive(Eq, Debug)

///|
/// Add the immutable domain packet ONCE to actual original outside extents.
/// The entering caller already backs its borrowed inputs/getter/current/resize
/// frame. This is not a prepaid entrance or physical-backing supplier.
pub fn[I, P] begin_parameter_binding_preparation(
  capacity : @resources.PreparationCapacity[I, P],
  input : I,
  declarations : @parameters.Declarations,
  supplied : @decode.Cursor?,
  limits : @admitted.Limits,
) -> Result[
  ClientParameterBindingPreparation[I, P],
  ClientParameterBindingPreparationIssue,
] {
  let (base_retained, base_execution) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(
      base_retained, parameter_binding_initial_bytes, 1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(
      base_execution, parameter_binding_initial_bytes, 1L,
    )
    is Some(e) else {
    return Err(Overflow)
  }
  match @resources.reserve_working_preparation_phase(capacity, input, r, e) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  let prepared = @parameters.prepare_binding_read(
    declarations, supplied, limits,
  )
  let depth = match prepared {
    Err(_) => 0
    Ok(_) => {
      let maximum = match supplied {
        None => 0L
        Some(cursor) => @decode.admission_usage(cursor).nodes.to_int64()
      }
      let receipt = match
        @resources.begin_preparation_phase_work64(
          capacity,
          input,
          @resources.ParameterBindingHeaderInventory,
          maximum,
        ) {
        Err(issue) => return Err(Work(issue))
        Ok(receipt) => receipt
      }
      let (depth, spent) = match supplied {
        None => (0, 0L)
        Some(cursor) => @decode.observe_cursor_path_depth(cursor)
      }
      let charged = @resources.spend_preparation_phase_work64(receipt, spent)
      match @resources.finish_preparation_phase_work64(receipt) {
        Err(issue) => return Err(Work(issue))
        Ok(_) => ()
      }
      match charged {
        Err(issue) => return Err(Work(issue))
        Ok(_) => depth
      }
    }
  }
  Ok({
    capacity,
    input: Some(input),
    prepared: Some(prepared),
    quote: None,
    work: None,
    current: None,
    step: @parameters.BindingHeader,
    body_bytes: 0L,
    maximum_work: 0L,
    source_input: None,
    source: None,
    base_retained,
    base_execution,
    depth,
    busy: false,
    phase: BindingInitial,
  })
}

///|
/// Grow before closed-object/key-map/names/reader construction. Retry retains
/// the same original semantic reader and quote; it never rereads declarations.
pub fn[I, P] prepare_parameter_binding_header(
  owner : ClientParameterBindingPreparation[I, P],
) -> Result[Unit, ClientParameterBindingPreparationIssue] {
  guard !owner.busy &&
    (owner.phase == BindingInitial || owner.phase == BindingHeaderQuoted) &&
    owner.input is Some(input) &&
    owner.prepared is Some(Ok(original)) &&
    @parameters.binding_read_phase(original) == @parameters.BindingHeader else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_parameter_binding_header_owned(owner, input, original)
  owner.busy = false
  result
}

///|
fn[I, P] prepare_parameter_binding_header_owned(
  owner : ClientParameterBindingPreparation[I, P],
  input : I,
  original : @parameters.BindingReadInput,
) -> Result[Unit, ClientParameterBindingPreparationIssue] {
  if owner.phase == BindingInitial {
    guard parameter_binding_header_construction_bytes(original, owner.depth)
      is Some(bytes) &&
      @execution.checked_preparation_add_product(
        parameter_binding_initial_bytes, bytes, 1L,
      )
      is Some(total) &&
      @execution.checked_preparation_add_product(owner.base_retained, total, 1L)
      is Some(r) &&
      @execution.checked_preparation_add_product(
        owner.base_execution,
        total,
        1L,
      )
      is Some(e) else {
      return Err(Overflow)
    }
    owner.quote = Some((r, e))
    owner.body_bytes = bytes
    owner.phase = BindingHeaderQuoted
  }
  let (r, e) = owner.quote.unwrap()
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  // Currentness may call out/reenter. It must not turn this Header reserve
  // into permission to advance an already changed reader into Value work.
  guard @parameters.binding_read_phase(original) == @parameters.BindingHeader else {
    return Err(WrongPhase)
  }
  @parameters.advance_binding_read(original)
  owner.phase = BindingHeaderPrepared
  Ok(())
}

///|
/// Same retained original/Result, not a ready bindings assertion. Later reader
/// constructors still need their own complete same-parent backing before use.
pub fn[I, P] parameter_binding_preparation_outcome(
  owner : ClientParameterBindingPreparation[I, P],
) -> Result[@parameters.BindingReadInput, @parameters.Issue]? {
  if owner.busy || owner.phase == BindingRetired {
    None
  } else {
    owner.prepared
  }
}

///|
/// Drop only this continuation's references. Original escaped input/result
/// aliases and SAME parent remain charged; no settle/shrink/physical ACK.
pub fn[I, P] clear_parameter_binding_preparation(
  owner : ClientParameterBindingPreparation[I, P],
) -> Result[Unit, ClientParameterBindingPreparationIssue] {
  if owner.busy || owner.work is Some(_) {
    return Err(WrongPhase)
  }
  owner.input = None
  owner.prepared = None
  owner.quote = None
  owner.current = None
  owner.source_input = None
  owner.source = None
  owner.phase = BindingRetired
  Ok(())
}
