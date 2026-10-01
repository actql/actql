///|
/// Identity context for one checked, source-free INFER occurrence. It is not
/// a dispatch permission, completed model capture or reusable egress grant.
pub struct ClientInferCallScope {
  owner : PreparedClientProgram
  plan : ClientInferPlanGraph
  input : @execution.CompletedOutput
  artifact : @publication.RunEvidenceValue
  effective : @publication.RunEvidenceValue
  unit_definition_cid : String
  source_ordinal : Int
}

///|
pub(all) enum ClientInferCallScopeIssue {
  ForeignOwner
  ForeignInput
  UnsupportedBindings
  Encoding
  Evidence(@publication.RunEvidenceValueIssue)
}

///|
/// Bind the actual completed input and its exact export receipt. This initial
/// route has no Stage inputs or opaque bindings; their nonempty variants need
/// their existing acquisition/authority owners, not caller-provided CID maps.
pub fn issue_prepared_client_infer_call_scope(
  owner : PreparedClientProgram,
  plan : ClientInferPlanGraph,
  step : Int,
  input : @execution.CompletedOutput,
  receipt : @execution.CompletedRelationExportReceipt,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientInferCallScope, ClientInferCallScopeIssue] {
  guard physical_equal(owner, plan.owner) &&
    plan.source_ordinal == step &&
    client_infer_prefix_owner(owner, 0, step) is Some(prefix) &&
    @checked.unit_definition_cid(@strategy.graph_program(owner.graph), 0)
    is Some(unit_definition_cid) else {
    return Err(ForeignOwner)
  }
  if !@execution.completed_output_matches_port(
      input,
      prefix,
      @pipeline.Step(step - 1),
    ) ||
    !@execution.completed_relation_export_matches_output(receipt, input) {
    return Err(ForeignInput)
  }
  let bindings = match
    issue_prepared_client_empty_invocation_bindings(
      owner, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(UnsupportedBindings)
  }
  let identity = prepared_client_identity(owner)
  let effective_body = "{\"version\":\"actql-model-effective-inputs/0.1\"," +
    "\"parameter_values_cid\":\"" +
    identity.parameter_values_cid +
    "\",\"invocation_bindings_cid\":\"" +
    @publication.run_evidence_value_identity(bindings) +
    "\",\"input_artifacts\":{}}"
  let effective = match
    @publication.seal_run_evidence_value(
      "model_effective_inputs", effective_body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  let artifact_body = "{\"version\":\"actql-model-input-artifact/0.1\"," +
    "\"program_definition_cid\":\"" +
    identity.program_definition_cid +
    "\",\"unit_definition_cid\":\"" +
    unit_definition_cid +
    "\",\"source_ordinal\":" +
    step.to_string() +
    ",\"effective_inputs_cid\":\"" +
    @publication.run_evidence_value_identity(effective) +
    "\",\"input_fragment_cid\":\"" +
    plan.input_fragment_cid +
    "\",\"logical_relation_cid\":\"" +
    @execution.logical_relation_cid(
      @execution.completed_relation_export_identity(receipt),
    ) +
    "\",\"relation_schema_cid\":\"" +
    @execution.relation_schema_cid(
      @execution.completed_relation_export_schema_identity(receipt),
    ) +
    "\",\"ordered_rows_cid\":\"" +
    @execution.output_stream_identity(
      @execution.completed_relation_export_content(receipt),
    ).0 +
    "\",\"completeness\":\"complete\"}"
  let artifact = match
    @publication.seal_run_evidence_value(
      "model_input_artifact", artifact_body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  Ok({
    owner,
    plan,
    input,
    artifact,
    effective,
    unit_definition_cid,
    source_ordinal: step,
  })
}

///|
pub fn client_infer_call_scope_matches(
  value : ClientInferCallScope,
  owner : PreparedClientProgram,
  input : @execution.CompletedOutput,
) -> Bool {
  physical_equal(value.owner, owner) &&
  @execution.completed_output_available(input) &&
  @execution.completed_output_same_occurrence(value.input, input)
}

///|
pub fn client_infer_call_scope_artifact(
  value : ClientInferCallScope,
) -> @publication.RunEvidenceValue {
  value.artifact
}

///|
pub fn client_infer_call_scope_matches_rows(
  value : ClientInferCallScope,
  rows : @execution.PreparedInferRows,
  fixed_request_cid : String,
) -> Bool {
  fixed_request_cid == value.plan.request_cid &&
  @execution.prepared_infer_rows_matches_completed_input(rows, value.input) &&
  physical_equal(
    @infer.model_task(@execution.prepared_infer_rows_owner(rows)),
    @environment.model_execution_task(value.plan.execution),
  )
}

///|
/// The key identity is supplied by the typed request-preparation owner. This
/// value remains identity material, never proof that a model has been called.
pub fn issue_client_infer_call_slot(
  value : ClientInferCallScope,
  key : @publication.RunEvidenceValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.RunEvidenceValue, ClientInferCallScopeIssue] {
  if !@execution.completed_output_available(value.input) ||
    @publication.run_evidence_value_name(key) != "model_input_key" {
    return Err(ForeignInput)
  }
  let identity = prepared_client_identity(value.owner)
  let body = "{\"version\":\"actql-model-call-slot/0.1\"," +
    "\"program_definition_cid\":\"" +
    identity.program_definition_cid +
    "\",\"unit_definition_cid\":\"" +
    value.unit_definition_cid +
    "\",\"source_ordinal\":" +
    value.source_ordinal.to_string() +
    ",\"effective_inputs_cid\":\"" +
    @publication.run_evidence_value_identity(value.effective) +
    "\",\"input_artifact_cid\":\"" +
    @publication.run_evidence_value_identity(value.artifact) +
    "\",\"input_key_cid\":\"" +
    @publication.run_evidence_value_identity(key) +
    "\",\"model_task_cid\":\"" +
    @environment.model_task_identity(
      @environment.model_execution_task(value.plan.execution),
    ).2 +
    "\",\"fixed_request_cid\":\"" +
    value.plan.request_cid +
    "\"}"
  @publication.seal_run_evidence_value(
    "model_call_slot", body, max_wire_bytes, max_nodes, max_depth,
  ).map_err(issue => Evidence(issue))
}
