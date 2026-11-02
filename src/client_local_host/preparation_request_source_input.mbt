///|
// One original Source continuation on the existing Request, not a Resource
// or cleanup Owner. The entrance's prepaid fixed group holds this quote record.
priv struct ClientRequestSourceInput {
  environment : @checked.CheckEnvironment
  publication : String
  quote : (Int64, Int64)
  mut attempted : Bool
  mut outcome : Result[
    @publication_host.ClientSourceInput,
    @publication_host.ClientSourcePreparationIssue,
  ]?
  mut handoff_quote : (Int64, Int64)?
}

///|
pub suberror ClientRequestSourceInputIssue {
  Source(@publication_host.ClientSourcePreparationIssue)
}

///|
pub impl Debug for ClientRequestSourceInputIssue with fn to_repr(self) {
  let original : Error = self
  Repr(original)
}

///|
// Source/canonical admission and Source/index construction coexist here.
// Reuse both existing input-derived representations, with one coarse fixed
// Source trace/return/failure group. These are demand, not policy maxima.
fn[I] request_source_input_construction_bytes(
  owner : ClientRequestPreparation[I],
) -> Int64? {
  let limits = @publication_host.client_standard_program_preparation_limits().checking.input
  guard request_intent_construction_bytes(
      owner.snapshot_units,
      owner.snapshot_values,
    )
    is Some(canonical) &&
    request_native_tree_units(
      owner.snapshot_units,
      owner.snapshot_values,
      limits,
    )
    is Some(tree) &&
    @execution.preparation_representation_cost(tree) is Some(source) &&
    @execution.preparation_representation_cost({
      record_headers: 32L,
      reference_slots: 96L,
      scalar_words: 64L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(controls) &&
    @execution.checked_preparation_add_product(canonical, source, 1L)
    is Some(bytes) &&
    @execution.checked_preparation_add_product(bytes, controls, 1L)
    is Some(bytes) else {
    return None
  }
  Some(bytes)
}

///|
/// Admit the SAME retained submitted Source under its existing Request debit.
/// No raw Source frame escapes this caller, and no second intent is issued.
pub fn[I] prepare_request_source_input(
  owner : ClientRequestPreparation[I],
  input : I,
  environment : @checked.CheckEnvironment,
  publication : String,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == Open &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    request_intent_input_ready(owner) &&
    owner.submitted_intent is Some(intent) &&
    owner.query_syntax is None &&
    owner.program_json is None else {
    return Err(WrongPhase)
  }
  if owner.source_input is None {
    guard request_source_input_construction_bytes(owner) is Some(bytes) else {
      return Err(Policy)
    }
    let (r, e) = match
      @resources.preparation_capacity_working_extents(owner.capacity, input) {
      Err(issue) => return Err(Capacity(issue))
      Ok(value) => value
    }
    guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
      @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
      return Err(Policy)
    }
    owner.source_input = Some({
      environment,
      publication,
      quote: (r, e),
      attempted: false,
      outcome: None,
      handoff_quote: None,
    })
  }
  let selected = owner.source_input.unwrap()
  if !physical_equal(selected.environment, environment) ||
    selected.publication != publication {
    return Err(ForeignOriginal)
  }
  if selected.outcome is Some(result) {
    return result.map(_ => ()).map_err(issue => SourceInput(Source(issue)))
  }
  if selected.attempted {
    return Err(WrongPhase)
  }
  owner.phase = Selecting
  let reserved = @resources.reserve_working_preparation_phase(
    owner.capacity,
    input,
    selected.quote.0,
    selected.quote.1,
  )
  if reserved is Err(issue) {
    owner.phase = Open
    return Err(Capacity(issue))
  }
  // Retain the invocation marker before this constructor can fail or unwind.
  selected.attempted = true
  let result = @publication_host.prepare_client_source_input(
    intent,
    selected.environment,
    selected.publication,
  )
  selected.outcome = Some(result)
  if result is Ok(source) {
    match @publication_host.client_source_input_parts(source) {
      Err(issue) => {
        owner.phase = Open
        return Err(SourceInput(Source(issue)))
      }
      Ok((_, _, _, supplied)) => {
        owner.native_parameters = supplied
        owner.native_parameters_ready = true
      }
    }
  }
  owner.phase = Open
  result.map(_ => ()).map_err(issue => SourceInput(Source(issue)))
}

///|
fn[I] request_source_input_original(
  owner : ClientRequestPreparation[I],
) -> @publication_host.ClientSourceInput? {
  guard owner.source_input is Some(selected) &&
    selected.outcome is Some(Ok(source)) &&
    owner.submitted_intent is Some(intent) &&
    @publication_host.client_source_input_matches(
      source,
      intent,
      selected.environment,
      selected.publication,
    ) else {
    return None
  }
  Some(source)
}

///|
/// Borrowed parser inputs only. The original caller must keep its input loan.
pub fn[I] request_source_input_parts(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[
  (String, @frontend.Format, String?, @decode.Cursor?),
  ClientRequestPreparationIssue,
] {
  guard owner.phase != Selecting &&
    owner.phase != Retiring &&
    owner.phase != Closed &&
    owner.phase != Selected &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    request_source_input_original(owner) is Some(source) else {
    return Err(ForeignOriginal)
  }
  @publication_host.client_source_input_parts(source).map_err(issue => {
    SourceInput(Source(issue))
  })
}

///|
/// The Source profile walk reuses the complete original typed-data estimate
/// as an additional scratch envelope. Source/return/failure controls already
/// coexist in the selected Source intake quote; no policy ceiling is charged.
fn[I] request_source_handoff_quote(
  owner : ClientRequestPreparation[I],
  r : Int64,
  e : Int64,
) -> Result[(Int64, Int64), ClientRequestPreparationIssue] {
  guard owner.source_input is Some(source) && owner.program_data is Some(data) else {
    return Err(WrongPhase)
  }
  if source.handoff_quote is Some((retained, execution)) {
    return Ok((Int64::max(r, retained), Int64::max(e, execution)))
  }
  guard program_check_data_extent_cost(data) is Some(scratch) &&
    @execution.checked_preparation_add_product(e, scratch, 1L)
    is Some(execution) else {
    return Err(Policy)
  }
  source.handoff_quote = Some((r, execution))
  Ok((r, execution))
}

///|
fn[I, P, D] borrow_request_source_preparation_owned(
  owner : ClientRequestPreparation[I],
  input : I,
  capacity : @resources.PreparationCapacity[I, P],
  source : @publication_host.ClientSourceInput,
  prepared : D,
  retain_original : (@publication_host.ClientSourceInput, D) -> Result[
    @publication_host.ClientSourcePreparation,
    @publication_host.ClientSourcePreparationIssue,
  ],
) -> Result[
  @resources.PreparationBodyBorrow[@publication_host.ClientSourcePreparation],
  ClientRequestPreparationIssue,
] {
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  let (r, e) = match request_source_handoff_quote(owner, r, e) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let previous = owner.phase
  owner.phase = Selecting
  let reserved = @resources.reserve_working_preparation_phase(
    capacity, input, r, e,
  )
  if reserved is Err(issue) {
    owner.phase = previous
    return Err(Capacity(issue))
  }
  // The original Source input retains this return before the next current
  // boundary, including a failed borrower construction. It never recompiles.
  let retained = match retain_original(source, prepared) {
    Err(issue) => {
      owner.phase = previous
      return Err(SourceInput(Source(issue)))
    }
    Ok(value) => value
  }
  let result = @resources.reserve_preparation_construction_input(
    capacity, input, retained, r, e,
  )
  owner.phase = previous
  result.map_err(issue => Capacity(issue))
}

///|
/// SAME Resource construction borrower, not a completed Plan or Run grant.
/// The caller retains it across returned frames/awaits and returns it through
/// the existing Resource engine before Request/Run retirement can finish.
pub fn[I] borrow_request_source_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[
  @resources.PreparationBodyBorrow[@publication_host.ClientSourcePreparation],
  ClientRequestPreparationIssue,
] {
  guard owner.input is Some(original) &&
    physical_equal(original, input) &&
    request_source_input_original(owner) is Some(source) else {
    return Err(ForeignOriginal)
  }
  match
    (
      owner.phase,
      owner.program_capacity,
      owner.compiled_program,
      owner.effect_capacity,
      owner.compiled_effect,
    ) {
    (
      ProgramCompiled
      | ProgramPlanQuoted
      | ProgramPlanReserved,
      Some(capacity),
      Some(prepared),
      None,
      None,
    ) =>
      borrow_request_source_preparation_owned(
        owner, input, capacity, source, prepared, @publication_host.retain_compiled_client_source_pure_input,
      )
    (
      EffectCompiled
      | EffectPlanQuoted
      | EffectPlanReserved,
      None,
      None,
      Some(capacity),
      Some(prepared),
    ) =>
      borrow_request_source_preparation_owned(
        owner, input, capacity, source, prepared, @publication_host.retain_compiled_client_source_effect_input,
      )
    _ => Err(WrongPhase)
  }
}

///|
// Cut aliases only; original Resource borrowers and physical ACK remain owned
// by their existing engines, including a Source borrower still being used.
fn[I] clear_request_source_input(owner : ClientRequestPreparation[I]) -> Unit {
  if owner.source_input is Some(selected) &&
    selected.outcome is Some(Ok(source)) {
    @publication_host.clear_client_source_input(source)
  }
  owner.source_input = None
}
