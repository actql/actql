///|
// One input-proportional parse/index peak using existing common units. The
// original document stays borrowed. Parse Nodes/decoded Strings and the new
// index coexist until the parser returns; fixed controls use the original
// Program phase's installed Host baseline. No parser, tariff or cap is added.
fn request_document_parse_bytes(
  document : String,
  limits : @syntax.Limits,
) -> Int64? {
  let units = document.length().to_int64()
  let nodes = Int64::min(
    units + 1L,
    Int::max(1, limits.source.max_nodes).to_int64(),
  )
  @execution.execution_capacity_inventory_bytes([
    { unit: @execution.ValueNodeSlots, count: nodes, copies: 2, },
    { unit: @execution.DecodedTextBytes, count: units, copies: 2, },
    {
      unit: @execution.QuotedBytes,
      count: program_json_initial_control_bytes,
      copies: 1,
    },
  ])
}

///|
// Exact selected grammar, one original parser/index, same Program phase.
// Reconcile only after the synchronous parser/AST frame has returned, keeping
// the admitted index's actual Strings/spans/backing through the existing driver.
fn[I] prepare_request_document_input(
  owner : ClientRequestPreparation[I],
  input : I,
  document : String,
  format : @syntax.Format,
  limits : @syntax.Limits,
) -> Result[
  ClientProgramJsonPreparation[I, Unit],
  ClientRequestPreparationIssue,
] {
  guard owner.phase == Open &&
    owner.native_parameters_ready &&
    request_intent_input_ready(owner) &&
    owner.program_json is None else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  guard format == @syntax.Json || format == @syntax.Yaml else {
    return Err(Parameters(@local_preparation.InvalidFormat))
  }
  let (r0, e0) = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  guard request_document_parse_bytes(document, limits) is Some(bytes) &&
    @execution.checked_preparation_add_product(r0, bytes, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(e0, bytes, 1L) is Some(e) else {
    return Err(Policy)
  }
  owner.phase = Selecting
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
    Err(issue) => {
      owner.phase = ProgramJsonFailed
      return Err(Capacity(issue))
    }
    Ok(_) => ()
  }
  let indexed = match @syntax.parse_program_input(document, limits, format~) {
    Err(issue) => {
      owner.phase = ProgramJsonFailed
      return Err(ProgramJson(Syntax(issue)))
    }
    Ok(original) => original
  }
  let geometry = @decode.observe_subtree_construction_geometry(
    @syntax.program_input_cursor(indexed),
  )
  guard program_index_retained_units(
      indexed,
      geometry.fields,
      geometry.fields + geometry.texts,
      geometry.objects,
      geometry.arrays,
    )
    is Some(units) else {
    owner.phase = ProgramJsonFailed
    return Err(ProgramJson(Overflow))
  }
  let child = request_program_index_preparation(
    owner, input, indexed, units, limits, r0, e0,
  )
  child.phase = Indexed
  owner.program_json = Some(child)
  match reconcile_program_json_preparation_index(child) {
    Err(issue) => {
      owner.phase = ProgramJsonFailed
      return Err(ProgramJson(issue))
    }
    Ok(_) => ()
  }
  owner.phase = ProgramJson
  Ok(child)
}

///|
fn[I] prepare_request_document_computation_input(
  owner : ClientRequestPreparation[I],
  input : I,
  document : String,
  format : @syntax.Format,
  limits : @syntax.Limits,
) -> Result[Unit, ClientRequestTerminalIssue] {
  let source = match
    prepare_request_document_input(owner, input, document, format, limits) {
    Err(issue) => return Err(Preparation(issue))
    Ok(original) => original
  }
  match construct_program_json_preparation(source) {
    Err(issue) => return Err(Preparation(ProgramJson(issue)))
    Ok(_) => ()
  }
  match reconcile_program_json_preparation_structure(source) {
    Err(issue) => return Err(Preparation(ProgramJson(issue)))
    Ok(_) => ()
  }
  Ok(())
}
