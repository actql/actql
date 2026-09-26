///|
pub(all) enum ClientEffectLocalInvocationIssue {
  MissingUnit
  NotSourceFree
  ForeignCapturedInput
  MissingCapturedInput
  Encoding
} derive(Eq, Debug)

///|
/// Semantic identity for one checked, source-free local Unit. It does not
/// attest execution, capture, retention, or permission to apply an Effect.
struct ClientEffectLocalInvocation {
  owner : PreparedClientEffectComputation
  unit : Int
  unit_definition_cid : String
  cid : String
  wire : String
}

///|
fn emit_client_effect_local_invocation(
  writer : @encode.Writer,
  unit_definition_cid : String,
  used_values_cid : String,
  local_contracts_cid : String,
  policy_cid : String,
  self_cid : String?,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "local_contracts_cid")
  @encode.string_value(writer, local_contracts_cid)
  @encode.key(writer, "observation_cids")
  @encode.begin_array(writer)
  @encode.end_array(writer)
  @encode.key(writer, "policy_cid")
  @encode.string_value(writer, policy_cid)
  if self_cid is Some(cid) {
    @encode.key(writer, "self_cid")
    @encode.string_value(writer, cid)
  }
  @encode.key(writer, "unit_definition_cid")
  @encode.string_value(writer, unit_definition_cid)
  @encode.key(writer, "used_values_cid")
  @encode.string_value(writer, used_values_cid)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-local-computation-semantics/0.1")
  @encode.end_object(writer)
}

///|
/// Issue the local semantic Invocation from the checked owner. The first
/// Unit must begin with admitted Values and have no imported or external
/// observations. Other Units require a captured observation owner and cannot
/// use this source-free issuance path.
pub fn issue_source_free_client_effect_local_invocation(
  owner : PreparedClientEffectComputation,
  unit : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectLocalInvocation, ClientEffectLocalInvocationIssue] {
  let program = @checked.effect_program_static_checked_computation(
    owner.candidate,
  )
  guard @checked.unit_definition_cid(program, unit) is Some(unit_definition_cid) &&
    @checked.unit_used_values_cid(program, unit) is Some(used_values_cid) &&
    @checked.unit_contracts_cid(program, unit) is Some(local_contracts_cid) &&
    @checked.unit_pipeline(program, unit) is Some(pipeline) else {
    return Err(MissingUnit)
  }
  if unit != 0 ||
    @pipeline.input_count(pipeline) != 0 ||
    !@pipeline.starts_with_values(pipeline) ||
    @checked.unit_result_import_count(program, unit) != Some(0) ||
    @checked.unit_import_cid_count(program, unit) != Some(0) {
    return Err(NotSourceFree)
  }
  let policy_cid = @checked.checked_local_policy_cid(program)
  let hash = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_effect_local_invocation(
    hash,
    unit_definition_cid,
    used_values_cid,
    local_contracts_cid,
    policy_cid,
    None,
  ) catch {
    _ => return Err(Encoding)
  }
  let cid = "sha256:" +
    (@encode.finish_hash(hash) catch { _ => return Err(Encoding) })
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_effect_local_invocation(
    writer,
    unit_definition_cid,
    used_values_cid,
    local_contracts_cid,
    policy_cid,
    Some(cid),
  ) catch {
    _ => return Err(Encoding)
  }
  let wire = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok({ owner, unit, unit_definition_cid, cid, wire, })
}

///|
/// Resolve the Unit coordinate from the live checked Effect source pin.
pub fn issue_source_free_captured_client_effect_local_invocation(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectLocalInvocation, ClientEffectLocalInvocationIssue] {
  if !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) {
    return Err(ForeignCapturedInput)
  }
  guard @strategy.captured_effect_input_at(inputs, member_index) is Some(input) else {
    return Err(MissingCapturedInput)
  }
  issue_source_free_client_effect_local_invocation(
    owner,
    @strategy.captured_effect_input_stage(input),
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
pub fn client_effect_local_invocation_cid(
  value : ClientEffectLocalInvocation,
) -> String {
  value.cid
}

///|
pub fn client_effect_local_invocation_json(
  value : ClientEffectLocalInvocation,
) -> String {
  value.wire
}

///|
/// A CID copied from another checked Unit or preparation is not a substitute
/// for the owner that issued this local Invocation.
pub fn client_effect_local_invocation_matches(
  value : ClientEffectLocalInvocation,
  owner : PreparedClientEffectComputation,
  unit : Int,
) -> Bool {
  if !physical_equal(value.owner, owner) || value.unit != unit {
    return false
  }
  let program = @checked.effect_program_static_checked_computation(
    owner.candidate,
  )
  @checked.unit_definition_cid(program, unit) == Some(value.unit_definition_cid)
}
