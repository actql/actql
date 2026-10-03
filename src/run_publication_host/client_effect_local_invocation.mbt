///|
pub(all) enum ClientEffectLocalInvocationIssue {
  MissingUnit
  NotSourceFree
  ForeignCapturedInput
  MissingCapturedInput
  ForeignSourceObservation
  IncompleteResultImports
  ForeignResultImport
  Encoding
} derive(Eq, Debug)

///|
/// Semantic identity for one checked local Unit. It does not
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
  observation_cids : Array[String],
  self_cid : String?,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "local_contracts_cid")
  @encode.string_value(writer, local_contracts_cid)
  @encode.key(writer, "observation_cids")
  @encode.begin_array(writer)
  for cid in observation_cids {
    @encode.string_value(writer, cid)
  }
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
  issue_client_effect_local_invocation_body(
    owner,
    unit,
    unit_definition_cid,
    used_values_cid,
    local_contracts_cid,
    @checked.checked_local_policy_cid(program),
    [],
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn issue_client_effect_local_invocation_body(
  owner : PreparedClientEffectComputation,
  unit : Int,
  unit_definition_cid : String,
  used_values_cid : String,
  local_contracts_cid : String,
  policy_cid : String,
  observations : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectLocalInvocation, ClientEffectLocalInvocationIssue] {
  let hash = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_effect_local_invocation(
    hash,
    unit_definition_cid,
    used_values_cid,
    local_contracts_cid,
    policy_cid,
    observations,
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
    observations,
    Some(cid),
  ) catch {
    _ => return Err(Encoding)
  }
  let wire = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok({ owner, unit, unit_definition_cid, cid, wire, })
}

///|
/// Bind the acquired root Unit to the completed capture and its admitted
/// observation. This is not the Run-wide Invocation or a read/apply permit.
/// Imported Results require their own dependency closure, not this entry.
pub fn issue_acquired_client_effect_local_invocation(
  owner : PreparedClientEffectComputation,
  captured : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  input : @publication.RunEvidenceValue,
  observation : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  data_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  unit? : Int = 0,
) -> Result[ClientEffectLocalInvocation, ClientEffectLocalInvocationIssue] {
  let program = @checked.effect_program_static_checked_computation(
    owner.candidate,
  )
  let graph = @strategy.checked_effect_computation_graph(owner.graph)
  if unit < 0 || unit >= @strategy.graph_captured_prefix(graph) {
    return Err(MissingUnit)
  }
  guard @strategy.graph_task_owner(graph, unit) is Some(first) &&
    @checked.unit_definition_cid(program, unit) is Some(definition) &&
    @checked.unit_used_values_cid(program, unit) is Some(values) &&
    @checked.unit_contracts_cid(program, unit) is Some(contracts) &&
    @checked.unit_pipeline(program, unit) is Some(pipeline) else {
    return Err(MissingUnit)
  }
  let source_owner = @checked.source_identity(@strategy.graph_program(graph))
  if @pipeline.starts_with_values(pipeline) ||
    @checked.unit_result_import_count(program, unit) != Some(0) ||
    @checked.unit_import_cid_count(program, unit) != Some(0) ||
    !@query.captured_source_matches(captured, source_owner, first) ||
    !@query.captured_source_relation_identity_matches_source(identity, captured) ||
    !physical_equal(
      @planning.query_requirement_program(requirement),
      source_owner,
    ) ||
    !physical_equal(
      @query.query_sequence_owner(
        @planning.query_material_owner(
          @planning.query_requirement_material(requirement),
        ),
      ),
      first,
    ) {
    return Err(ForeignCapturedInput)
  }
  let (source_ref, source_contract) = @planning.query_requirement_source(
    requirement,
  )
  // The installed bounded snapshot profile currently promises no ordering.
  if @publication.admit_completed_source_input_logical(
      input,
      @query.captured_source_relation_logical_cid(identity),
      @query.captured_source_relation_schema_cid(identity),
      source_contract,
      "{\"stable\":false,\"keys\":[]}",
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    is Err(_) ||
    @publication.admit_completed_source_observation_binding(
      observation, input, source_ref, source_contract, authority_scope_cid, data_policy_cid,
      max_wire_bytes, max_nodes, max_depth,
    )
    is Err(_) {
    return Err(ForeignSourceObservation)
  }
  issue_client_effect_local_invocation_body(
    owner,
    unit,
    definition,
    values,
    contracts,
    @checked.checked_local_policy_cid(program),
    [@publication.run_evidence_value_identity(observation)],
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
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
