///|
/// Select the Content constructor before allocating its Plan. The same
/// original compiler is borrowed through the existing capacity engine; only
/// the two selected Plan/Request link carriers is added to the original Plan quote.
/// Subsequent borrows preserve actual domain growth without adding it again.
/// Selected provider/keyed/serialization backing remains separately required
/// on this SAME parent, never a second Root or a successful DATA quote.
pub fn[I] borrow_request_content_plan_input(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
  ClientRequestPreparationIssue,
] {
  if owner.program_source_free is Some(_) ||
    owner.program_captured is Some(_) ||
    owner.program_artifact_inputs is Some(_) ||
    owner.program_body_attempted {
    return Err(WrongPhase)
  }
  let reserved = owner.phase == ContentPlanReserved
  let (r, e) = match request_program_plan_quote(owner, input) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let capacity = owner.program_capacity.unwrap()
  let prepared = owner.compiled_program.unwrap()
  let (r, e) = if reserved {
    match @resources.preparation_capacity_working_extents(capacity, input) {
      Err(issue) => return Err(Capacity(issue))
      Ok(value) => value
    }
  } else {
    // Selected Plan and original Request links:2H2R2W. Fields are prepaid at entry.
    guard @execution.preparation_representation_cost({
        record_headers: 2L,
        reference_slots: 2L,
        scalar_words: 2L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      })
      is Some(bytes) &&
      @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
      @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
      return Err(Policy)
    }
    (r, e)
  }
  owner.phase = Selecting
  let result = @resources.reserve_preparation_construction_input(
    capacity, input, prepared, r, e,
  )
  owner.phase = if result is Ok(_) || reserved {
    ContentPlanReserved
  } else {
    ProgramPlanQuoted
  }
  result.map_err(issue => Capacity(issue))
}

///|
/// Complete the actual selected keyed Content preparation on the original
/// compiled Program capacity. The caller retains its construction borrow and
/// all external domain material until this synchronous handoff has unwound.
/// The retained link carriers were funded before construction; no quote repeats.
pub fn[I] complete_request_content_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  selected : ClientInstalledManagedKeyedPreparation,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == ContentPlanReserved &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_source_free is None &&
    owner.program_captured is None &&
    owner.program_keyed is None else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) &&
    physical_equal(original, input) &&
    physical_equal(selected.prepared, prepared) else {
    return Err(ForeignOriginal)
  }
  let identity = @publication_host.prepared_client_identity(prepared)
  if identity.program_definition_cid !=
    @publication_host.client_request_program_cid(request) ||
    identity.parameter_values_cid !=
    @publication_host.client_request_parameters_cid(request) {
    return Err(ForeignOriginal)
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  owner.phase = Selecting
  owner.program_keyed = Some(selected)
  owner.program_content_request = Some(request)
  owner.program_body_attempted = true
  let result = @resources.complete_preparation_capacity(
    capacity, input, prepared, r, e,
  )
  owner.phase = if result is Ok(_) {
    ProgramBodyReady
  } else {
    ProgramBodyFailed
  }
  result.map_err(issue => Capacity(issue))
}

///|
/// Same-parent adoption retains the original Content Plan through currentness
/// and generic preparation retirement. The legacy Content purpose is neither
/// selected nor widened. No Source read or provider operation begins here.
pub fn[I] begin_request_content_managed_run(
  owner : ClientRequestPreparation[I],
  request : @publication_host.ClientRequestIdentity,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  guard owner.phase == ProgramBodyReady &&
    owner.input is Some(input) &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_keyed is Some(selected) &&
    owner.program_content_request is Some(original_request) &&
    physical_equal(original_request, request) else {
    return Err(ForeignOriginal)
  }
  owner.phase = Selecting
  let result = begin_preparation_owned_installed_content_run(
    owner.initial,
    input,
    capacity,
    prepared,
    request,
    selected,
  )
  match result {
    Err(issue) => {
      owner.phase = ProgramBodyReady
      Err(issue)
    }
    Ok(run) => {
      owner.program_capacity = None
      owner.compiled_program = None
      owner.program_data = None
      owner.program_plan_quote = None
      owner.program_keyed = None
      owner.program_content_request = None
      owner.native_parameters = None
      owner.native_query_declarations = None
      owner.native_parameters_ready = false
      owner.held_program = None
      owner.submitted_intent = None
      owner.intent_base = None
      owner.intent_peak_live = false
      owner.input = None
      owner.query_syntax = None
      owner.phase = Selected
      Ok(run)
    }
  }
}
