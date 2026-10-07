///|
/// A private closed input is a distinct checked producer, never a published
/// Result with a different name. The Unit identity includes its authored
/// source and projection; the opaque occurrence fixes the live capture.
struct ClientEffectLocalTableDefinition {
  owner : PreparedClientEffectComputation
  unit : Int
  occurrence : @execution.ManagedTableInputOccurrence
  name : String
  unit_definition_cid : String
  cid : String
  wire : String
}

///|
fn emit_client_effect_local_table_definition(
  writer : @encode.Writer,
  unit_definition_cid : String,
  name : String,
  self_cid : String?,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  if self_cid is Some(cid) {
    @encode.key(writer, "self_cid")
    @encode.string_value(writer, cid)
  }
  @encode.key(writer, "table_input_name")
  @encode.string_value(writer, name)
  @encode.key(writer, "unit_definition_cid")
  @encode.string_value(writer, unit_definition_cid)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-local-table-input-definition/0.1")
  @encode.end_object(writer)
}

///|
pub fn issue_captured_client_effect_local_table_definition(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientEffectLocalTableDefinition,
  ClientEffectLocalResultDefinitionIssue,
] {
  if !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) {
    return Err(ForeignCapturedInput)
  }
  guard @strategy.captured_effect_table_input_at(inputs, member_index)
    is Some(input) else {
    return Err(MissingCapturedInput)
  }
  let unit = @strategy.captured_effect_table_input_stage(input)
  let occurrence = @strategy.captured_effect_table_input_occurrence(input)
  let declaration = @execution.managed_table_input_occurrence_definition(
    occurrence,
  )
  let name = @results.table_input_name(declaration)
  let program = @checked.effect_program_static_checked_computation(
    owner.candidate,
  )
  guard @checked.unit_definition_cid(program, unit) is Some(unit_definition_cid) &&
    @stage_results.stage_table_inputs_at(
      @checked.checked_stage_results(program),
      unit,
    )
    is Some(declarations) &&
    @results.lookup_table_input(declarations, name) is Some(actual) &&
    physical_equal(actual, declaration) else {
    return Err(MissingUnit)
  }
  if name.is_empty() || @canonical_value.normalize_nfc_lf(name) != Ok(name) {
    return Err(NonCanonicalResultName)
  }
  let hash = @encode.hashing_writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_effect_local_table_definition(
    hash,
    unit_definition_cid,
    name,
    None,
  ) catch {
    _ => return Err(Encoding)
  }
  let cid = "sha256:" +
    (@encode.finish_hash(hash) catch { _ => return Err(Encoding) })
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_effect_local_table_definition(
    writer,
    unit_definition_cid,
    name,
    Some(cid),
  ) catch {
    _ => return Err(Encoding)
  }
  let wire = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok({ owner, unit, occurrence, name, unit_definition_cid, cid, wire, })
}

///|
pub fn client_effect_local_table_definition_cid(
  value : ClientEffectLocalTableDefinition,
) -> String {
  value.cid
}

///|
pub fn client_effect_local_table_definition_json(
  value : ClientEffectLocalTableDefinition,
) -> String {
  value.wire
}

///|
fn client_effect_local_table_definition_matches(
  value : ClientEffectLocalTableDefinition,
  owner : PreparedClientEffectComputation,
  input : @strategy.CapturedEffectTableInput,
) -> Bool {
  physical_equal(value.owner, owner) &&
  value.unit == @strategy.captured_effect_table_input_stage(input) &&
  physical_equal(
    @execution.managed_table_input_occurrence_owner(value.occurrence),
    @execution.managed_table_input_occurrence_owner(
      @strategy.captured_effect_table_input_occurrence(input),
    ),
  ) &&
  physical_equal(
    @execution.managed_table_input_occurrence_definition(value.occurrence),
    @execution.managed_table_input_occurrence_definition(
      @strategy.captured_effect_table_input_occurrence(input),
    ),
  ) &&
  @checked.unit_definition_cid(
    @checked.effect_program_static_checked_computation(owner.candidate),
    value.unit,
  ) ==
  Some(value.unit_definition_cid)
}
