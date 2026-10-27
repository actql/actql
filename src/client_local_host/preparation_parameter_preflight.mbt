///|
priv enum ParameterPreflightPhase {
  Initial
  Inspected
  Preflighted
  RetainedPreflight
  HeaderQuoted
  HeaderPrepared
  InventoryQuoted
  InventoryPrepared
  RetainedInventory
  TypeQuoted
  TypePrepared
  Failed
  Retired
} derive(Eq)

///|
/// A domain continuation over the SAME preparation reservation, never another
/// Resource Owner. Its source/default/meta backing remains with the entering
/// caller. Each actual constructor phase requires its own complete funding;
/// the current continuation stops before default/metadata body construction.
struct ClientParameterDeclarationPreflight[I, P] {
  capacity : @resources.PreparationCapacity[I, P]
  mut input : I?
  mut root : @decode.Cursor?
  limits : @parameters.DeclarationLimits
  mut geometry : @decode.SubtreeConstructionGeometry?
  mut quote : (Int64, Int64)?
  mut prepared : (
    Result[@parameters.DeclarationReadInput, @parameters.Issue],
    Int,
    Int,
  )?
  mut work : @resources.PreparationPhaseWork64?
  base_retained : Int64
  base_execution : Int64
  mut depth : Int
  mut body_bytes : Int64
  mut current_type : @decode.Cursor?
  mut current_type_facts : @parameters.DeclarationReadConstructionFacts?
  mut busy : Bool
  mut phase : ParameterPreflightPhase
}

///|
pub(all) enum ClientParameterDeclarationPreflightIssue {
  Capacity(@resources.PreparationCapacityIssue)
  Work(@resources.PreparationWorkIssue)
  WrongPhase
  Overflow
} derive(Eq, Debug)

///|
/// Add this immutable domain packet ONCE to the actual outside debit. The
/// entering getter/current/resize and borrowed source/limits already require
/// the caller's physical backing; this adds no prepaid or numerical supplier.
pub fn[I, P] begin_parameter_declaration_preflight(
  capacity : @resources.PreparationCapacity[I, P],
  input : I,
  root : @decode.Cursor?,
  limits : @parameters.DeclarationLimits,
) -> Result[
  ClientParameterDeclarationPreflight[I, P],
  ClientParameterDeclarationPreflightIssue,
] {
  let (base_retained, base_execution) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(
      base_retained, parameter_preflight_initial_bytes, 1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(
      base_execution, parameter_preflight_initial_bytes, 1L,
    )
    is Some(e) else {
    return Err(Overflow)
  }
  match @resources.reserve_working_preparation_phase(capacity, input, r, e) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  Ok({
    capacity,
    input: Some(input),
    root,
    limits,
    geometry: None,
    quote: None,
    prepared: None,
    work: None,
    base_retained,
    base_execution,
    depth: 0,
    body_bytes: 0L,
    current_type: None,
    current_type_facts: None,
    busy: false,
    phase: Initial,
  })
}

///|
/// Inspect once, finish its actual work receipt, then grow BEFORE the original
/// declaration preflight. Failed growth keeps its original geometry/quote;
/// neither its metadata scan nor Source/type/default acceptance is repeated.
pub fn[I, P] prepare_parameter_declaration_preflight(
  owner : ClientParameterDeclarationPreflight[I, P],
) -> Result[Unit, ClientParameterDeclarationPreflightIssue] {
  guard !owner.busy &&
    (owner.phase == Initial || owner.phase == Inspected) &&
    owner.input is Some(input) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_parameter_declaration_preflight_owned(owner, input)
  owner.busy = false
  result
}

///|
fn[I, P] prepare_parameter_declaration_preflight_owned(
  owner : ClientParameterDeclarationPreflight[I, P],
  input : I,
) -> Result[Unit, ClientParameterDeclarationPreflightIssue] {
  if owner.phase == Initial {
    match
      @resources.check_working_preparation_capacity_current(
        owner.capacity,
        input,
      ) {
      Err(issue) => return Err(Capacity(issue))
      Ok(_) => ()
    }
    let maximum = match owner.root {
      None => 0L
      Some(root) => 4L * @decode.admission_usage(root).nodes.to_int64()
    }
    let work = match
      @resources.begin_preparation_phase_work64(
        owner.capacity,
        input,
        @resources.ParameterDeclarationInventory,
        maximum,
      ) {
      Err(issue) => return Err(Work(issue))
      Ok(value) => value
    }
    owner.work = Some(work)
    let (geometry, depth, spent) = @parameters.observe_declaration_preflight_construction(
      owner.root,
      owner.limits,
    )
    let charged = @resources.spend_preparation_phase_work64(work, spent)
    match @resources.finish_preparation_phase_work64(work) {
      Err(issue) => return Err(Work(issue))
      Ok(_) => owner.work = None
    }
    match charged {
      Err(issue) => {
        owner.phase = Failed
        return Err(Work(issue))
      }
      Ok(_) => ()
    }
    owner.geometry = geometry
    owner.depth = depth
    owner.phase = Inspected
  }
  let quote = match owner.quote {
    Some(original) => original
    None => {
      let extra = match owner.geometry {
        None => 0L
        Some(original) => {
          guard parameter_preflight_construction_bytes(
              original,
              owner.depth,
              owner.limits,
            )
            is Some(value) else {
            return Err(Overflow)
          }
          value
        }
      }
      guard @execution.checked_preparation_add_product(
          parameter_preflight_initial_bytes, extra, 1L,
        )
        is Some(core) &&
        @execution.checked_preparation_add_product(
          owner.base_retained,
          core,
          1L,
        )
        is Some(r) &&
        @execution.checked_preparation_add_product(
          owner.base_execution,
          core,
          1L,
        )
        is Some(e) else {
        return Err(Overflow)
      }
      let quote = (r, e)
      owner.quote = Some(quote)
      quote
    }
  }
  if owner.geometry is Some(_) {
    match
      @resources.reserve_working_preparation_phase(
        owner.capacity,
        input,
        quote.0,
        quote.1,
      ) {
      Err(issue) => return Err(Capacity(issue))
      Ok(_) => ()
    }
  }
  let prepared = @parameters.prepare_declaration_read(owner.root, owner.limits)
  owner.prepared = Some(prepared)
  owner.phase = Preflighted
  Ok(())
}

///|
/// Borrow the SAME semantic continuation/outcome and original partial usage.
/// It still needs the next complete type/default/metadata reservation before
/// finish_declaration_read. This is not a complete declaration/Program check.
pub fn[I, P] parameter_declaration_preflight_outcome(
  owner : ClientParameterDeclarationPreflight[I, P],
) -> (Result[@parameters.DeclarationReadInput, @parameters.Issue], Int, Int)? {
  guard !owner.busy &&
    (
      owner.phase == Preflighted ||
      owner.phase == RetainedPreflight ||
      owner.phase == HeaderPrepared ||
      owner.phase == InventoryPrepared ||
      owner.phase == RetainedInventory ||
      owner.phase == TypePrepared
    ) &&
    owner.prepared is Some(_) else {
    return None
  }
  owner.prepared
}

///|
/// Called only after the original successful synchronous preflight returned.
/// Its arrays/normalizer/path scratch did not escape. Error outcomes keep
/// their original location backing and cannot use this success-only shrink.
/// Source/read-input/outside debits stay charged; no parent is settled.
pub fn[I, P] reconcile_parameter_declaration_preflight(
  owner : ClientParameterDeclarationPreflight[I, P],
) -> Result[Unit, ClientParameterDeclarationPreflightIssue] {
  guard !owner.busy &&
    owner.phase == Preflighted &&
    owner.input is Some(input) &&
    owner.prepared is Some((Ok(_), _, _)) else {
    return Err(WrongPhase)
  }
  guard @execution.checked_preparation_add_product(
      owner.base_retained,
      parameter_preflight_initial_bytes,
      1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(
      owner.base_execution,
      parameter_preflight_initial_bytes,
      1L,
    )
    is Some(e) else {
    return Err(Overflow)
  }
  owner.busy = true
  let result = @resources.reconcile_working_preparation_phase(
    owner.capacity,
    input,
    r,
    e,
  )
  owner.busy = false
  match result {
    Err(issue) => Err(Capacity(issue))
    Ok(_) => {
      owner.phase = RetainedPreflight
      Ok(())
    }
  }
}

///|
/// Drop only this domain's references. The outside owner still owns the SAME
/// reservation and all escaped input/outcome aliases. No settle, shrink,
/// physical stop or successful cleanup acknowledgement is inferred here.
pub fn[I, P] clear_parameter_declaration_preflight(
  owner : ClientParameterDeclarationPreflight[I, P],
) -> Result[Unit, ClientParameterDeclarationPreflightIssue] {
  if owner.busy || owner.work is Some(_) {
    return Err(WrongPhase)
  }
  owner.root = None
  owner.input = None
  owner.geometry = None
  owner.quote = None
  owner.prepared = None
  owner.current_type = None
  owner.current_type_facts = None
  owner.phase = Retired
  Ok(())
}
