///|
pub(all) enum ClientEffectLocalResultDefinitionIssue {
  MissingUnit
  MissingResult
  NonCanonicalResultName
  ForeignCapturedInput
  MissingCapturedInput
  Encoding
} derive(Eq, Debug)

///|
/// A checked Unit-local Result identity. This is intentionally distinct from
/// the Run-bound Program Result Definition used by publication.
struct ClientEffectLocalResultDefinition {
  owner : PreparedClientEffectComputation
  unit : Int
  result_name : String
  unit_definition_cid : String
  cid : String
  wire : String
}

///|
fn emit_client_effect_local_result_definition(
  writer : @encode.Writer,
  unit_definition_cid : String,
  result_name : String,
  self_cid : String?,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "result_name")
  @encode.string_value(writer, result_name)
  if self_cid is Some(cid) {
    @encode.key(writer, "self_cid")
    @encode.string_value(writer, cid)
  }
  @encode.key(writer, "unit_definition_cid")
  @encode.string_value(writer, unit_definition_cid)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-local-result-definition/0.1")
  @encode.end_object(writer)
}

///|
/// The checked owner, not a caller-provided CID or publication inventory,
/// proves that this Result is declared by this exact local Unit.
pub fn issue_client_effect_local_result_definition(
  owner : PreparedClientEffectComputation,
  unit : Int,
  result_name : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientEffectLocalResultDefinition,
  ClientEffectLocalResultDefinitionIssue,
] {
  let program = @checked.effect_program_static_checked_computation(
    owner.candidate,
  )
  guard @checked.unit_definition_cid(program, unit) is Some(unit_definition_cid) else {
    return Err(MissingUnit)
  }
  if result_name.is_empty() ||
    @canonical_value.normalize_nfc_lf(result_name) != Ok(result_name) {
    return Err(NonCanonicalResultName)
  }
  let stages = @checked.checked_stage_results(program)
  guard @stage_results.stage_at(stages, unit) is Some(stage) &&
    @results.lookup(stage, result_name) is Some(_) else {
    return Err(MissingResult)
  }
  let hash = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_effect_local_result_definition(
    hash,
    unit_definition_cid,
    result_name,
    None,
  ) catch {
    _ => return Err(Encoding)
  }
  let cid = "sha256:" +
    (@encode.finish_hash(hash) catch { _ => return Err(Encoding) })
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_effect_local_result_definition(
    writer,
    unit_definition_cid,
    result_name,
    Some(cid),
  ) catch {
    _ => return Err(Encoding)
  }
  let wire = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok({ owner, unit, result_name, unit_definition_cid, cid, wire, })
}

///|
/// Issue from a live checked Effect source pin. A name copied from an
/// unrelated Run cannot replace the captured source owner.
pub fn issue_captured_client_effect_local_result_definition(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientEffectLocalResultDefinition,
  ClientEffectLocalResultDefinitionIssue,
] {
  if !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) {
    return Err(ForeignCapturedInput)
  }
  guard @strategy.captured_effect_input_at(inputs, member_index) is Some(input) else {
    return Err(MissingCapturedInput)
  }
  issue_client_effect_local_result_definition(
    owner,
    @strategy.captured_effect_input_stage(input),
    @execution.managed_result_occurrence_name(
      @strategy.captured_effect_input_occurrence(input),
    ),
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
pub fn client_effect_local_result_definition_cid(
  value : ClientEffectLocalResultDefinition,
) -> String {
  value.cid
}

///|
pub fn client_effect_local_result_definition_json(
  value : ClientEffectLocalResultDefinition,
) -> String {
  value.wire
}

///|
pub fn client_effect_local_result_definition_matches(
  value : ClientEffectLocalResultDefinition,
  owner : PreparedClientEffectComputation,
  unit : Int,
  result_name : String,
) -> Bool {
  if !physical_equal(value.owner, owner) ||
    value.unit != unit ||
    value.result_name != result_name {
    return false
  }
  let program = @checked.effect_program_static_checked_computation(
    owner.candidate,
  )
  @checked.unit_definition_cid(program, unit) == Some(value.unit_definition_cid)
}
