///|
/// Identity context for one checked INFER occurrence. It is not
/// a dispatch permission, completed model capture or reusable egress grant.
pub struct ClientInferCallScope {
  owner : PreparedClientProgram
  plan : ClientInferPlanGraph
  input : @execution.CompletedOutput
  receipt : @execution.CompletedRelationExportReceipt
  artifact : @publication.RunEvidenceValue
  effective : @publication.RunEvidenceValue
  source : @publication.ModelSourceObservation?
  sources : Array[@publication.ModelSourceObservation]
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
/// Bind the completed input and its exact export receipt. An acquired input
/// supplies its checked capture owner, never a caller-provided CID map. Opaque
/// invocation bindings still require their separate authority admission.
pub fn issue_prepared_client_infer_call_scope(
  owner : PreparedClientProgram,
  plan : ClientInferPlanGraph,
  step : Int,
  input : @execution.CompletedOutput,
  receipt : @execution.CompletedRelationExportReceipt,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  captured? : ClientInferCapturedInput? = None,
) -> Result[ClientInferCallScope, ClientInferCallScopeIssue] {
  guard prepared_client_infer_execution_occurrence(owner, step)
    is Some(occurrence) else {
    return Err(ForeignOwner)
  }
  issue_client_infer_occurrence_call_scope(
    occurrence,
    plan,
    input,
    receipt,
    max_wire_bytes,
    max_nodes,
    max_depth,
    captured~,
  )
}

///|
/// Bind the actual Unit/task to the same completed-input identity owner used
/// by the installed component. A checked Effect view remains private here.
pub fn issue_client_infer_occurrence_call_scope(
  occurrence : ClientInferOccurrence,
  plan : ClientInferPlanGraph,
  input : @execution.CompletedOutput,
  receipt : @execution.CompletedRelationExportReceipt,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  captured? : ClientInferCapturedInput? = None,
  sources? : ClientInferComposedSources? = None,
) -> Result[ClientInferCallScope, ClientInferCallScopeIssue] {
  let owner = occurrence.owner
  let step = occurrence.step
  let prefix = occurrence.preparation
  if sources is Some(value) &&
    (
      captured is Some(_) ||
      !client_infer_composed_sources_matches(value, occurrence)
    ) {
    return Err(ForeignInput)
  }
  if captured is Some(value) &&
    client_infer_captured_input_source(value, owner, step) is None {
    return Err(ForeignInput)
  }
  if client_infer_occurrence_has_captured_sources(occurrence) &&
    captured is None &&
    sources is None {
    // An imported Source path needs its complete capture closure; it cannot
    // silently take the no-external-sources identity route.
    return Err(ForeignInput)
  }
  guard client_infer_occurrence_matches_plan(occurrence, plan) &&
    @checked.unit_definition_cid(
      @strategy.graph_program(owner.graph),
      occurrence.stage,
    )
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
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  let effective_body = try {
    @encode.begin_object(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-model-effective-inputs/0.1")
    @encode.key(writer, "parameter_values_cid")
    @encode.string_value(writer, identity.parameter_values_cid)
    @encode.key(writer, "invocation_bindings_cid")
    @encode.string_value(
      writer,
      @publication.run_evidence_value_identity(bindings),
    )
    @encode.key(writer, "input_artifacts")
    @encode.begin_object(writer)
    if captured is Some(value) {
      @encode.key(writer, value.name)
      @encode.string_value(
        writer,
        @publication.run_evidence_value_identity(value.logical),
      )
    }
    if sources is Some(value) {
      for input in value.inputs {
        @encode.key(writer, input.name)
        @encode.string_value(
          writer,
          @publication.run_evidence_value_identity(input.logical),
        )
      }
    }
    @encode.end_object(writer)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Encoding)
  }
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
    receipt,
    artifact,
    effective,
    source: captured.map(value => value.observation),
    sources: sources
    .map(client_infer_composed_source_observations)
    .unwrap_or([]),
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
  @execution.completed_output_same_occurrence(value.input, input) &&
  @execution.completed_relation_export_matches_output(value.receipt, input)
}

///|
pub fn client_infer_call_scope_artifact(
  value : ClientInferCallScope,
) -> @publication.RunEvidenceValue {
  value.artifact
}

///|
/// The exact bounded export receipt remains with the prepared call scope.
/// Its CIDs alone do not prove that the fixed input is held or replayable.
pub fn client_infer_call_scope_fixed_input_receipt(
  value : ClientInferCallScope,
) -> @execution.CompletedRelationExportReceipt {
  value.receipt
}

///|
/// Release the receipt's reference to its source after the call owner stops.
pub fn release_client_infer_call_scope(value : ClientInferCallScope) -> Unit {
  @execution.cancel_completed_relation_export_receipt(value.receipt)
}

///|
/// Saved replay matches the actual input even when its logical slot inventory
/// is empty. This validates original evidence, never fresh dispatch authority.
pub fn check_client_infer_saved_observation_scope(
  scope : ClientInferCallScope,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
) -> Result[Unit, @publication.RunEvidenceValueIssue] {
  @publication.check_saved_model_observation(
    admission,
    definition,
    observation,
    scope.artifact,
    prepared_client_identity(scope.owner).program_definition_cid,
    prepared_client_program_semantics_cid(scope.owner),
    prepared_client_check_environment_cid(scope.owner),
    @environment.model_task_data_handling_cid(
      @environment.model_execution_task(scope.plan.execution),
    ),
    source=scope.source,
    sources=scope.sources,
  )
}

///|
pub fn client_infer_call_scope_source_observations(
  scope : ClientInferCallScope,
) -> Array[@publication.ModelSourceObservation] {
  match scope.source {
    Some(value) => [value]
    None => scope.sources.copy()
  }
}

///|
pub fn client_infer_call_scope_matches_rows(
  value : ClientInferCallScope,
  rows : @execution.PreparedInferRows,
  fixed_request_cid : String,
) -> Bool {
  fixed_request_cid == value.plan.request_cid &&
  @execution.completed_relation_export_matches_output(
    value.receipt,
    value.input,
  ) &&
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
