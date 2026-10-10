///|
/// Recover this original generation as borrowed proof custody, not a fresh
/// CompletedOutput. Its authenticated saved Model scope provides the checked
/// Source closure; actual restored rows must still match that scope's artifact.
pub fn readmit_client_serialization_generation(
  run : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  scope : ClientInferSavedCallScope,
  evidence : @publication.BoundContentGeneration,
) -> Result[ClientSerializationGeneration, ClientSerializationGenerationIssue] {
  if !client_infer_saved_call_scope_matches_run(scope, run, definition) ||
    !client_infer_saved_call_scope_matches_occurrence(
      scope,
      scope.occurrence,
      plan,
    ) ||
    !client_serialization_recovery_matches_infer(
      run,
      definition,
      plan,
      scope.occurrence,
      evidence,
    ) {
    return Err(ForeignInput)
  }
  Ok({
    run,
    definition,
    evidence,
    output: None,
    captured: None,
    saved_scope: Some(scope),
  })
}

///|
/// Only restored custody exposes a saved scope. Fresh generation cannot
/// silently switch from checked completion to caller-authored saved rows.
pub fn client_serialization_generation_saved_scope_for(
  generation : ClientSerializationGeneration,
  run : ClientCompiledRun,
  plan : ClientInferPlanGraph,
) -> ClientInferSavedCallScope? {
  guard client_serialization_generation_available_for(generation, run) &&
    generation.saved_scope is Some(scope) &&
    client_infer_saved_call_scope_matches_occurrence(
      scope,
      scope.occurrence,
      plan,
    ) else {
    return None
  }
  Some(scope)
}

///|
/// Verify that borrowed generation evidence belongs to the selected original
/// compiled producer and consumer. This does not grant Model/Source authority.
pub fn client_serialization_recovery_matches_infer(
  run : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  occurrence : ClientInferOccurrence,
  evidence : @publication.BoundContentGeneration,
) -> Bool {
  guard check_client_compiled_run_definition(run, definition) is Ok(_) &&
    client_compiled_run_has_infer(run, plan) &&
    client_infer_occurrence_matches_compiled_run(occurrence, run) &&
    client_infer_occurrence_matches_plan(occurrence, plan) &&
    client_compiled_run_serialization(run) is Some(component) &&
    plan.serialization is Some(selected) &&
    physical_equal(component, selected) &&
    component.task == occurrence.task &&
    @publication.bound_content_generation_value(evidence) is Some(value) &&
    parse_plan_identity_value(
      @publication.run_evidence_value_json(value),
      16384,
      256,
      16,
    )
    is Some(body) else {
    return false
  }
  infer_scope_string(body, "bound_invocation_template_cid") ==
  Some(@publication.run_evidence_value_identity(run.template)) &&
  infer_scope_string(body, "run_definition_cid") ==
  Some(@publication.publication_contract_identity(definition)) &&
  infer_scope_string(body, "node_id") == Some(component.output.node_id) &&
  infer_scope_string(body, "barrier_cid") == Some(component.output.logical_cid)
}

///|
/// Borrow saved generation evidence under the original reconstructed checked
/// compilation. The authenticated Model-input receipt supplies the original
/// generation CID; the Store separately supplies a currently issued Ref.
/// This grants neither Source/Model permission nor a fresh CompletedOutput.
pub fn readmit_client_serialization_generation_evidence(
  run : ClientCompiledRun,
  definition : @publication.PublicationContract,
  expected_generation_cid : String,
  input : @publication.RunEvidenceValue,
  derivation : @publication.RunEvidenceValue,
  generation : @publication.RunEvidenceValue,
  candidate : @publication.StoredGeneratedContentReference,
  content : @admitted.CheckedValue,
) -> Result[
  @publication.BoundContentGeneration,
  ClientSerializationGenerationIssue,
] {
  if check_client_compiled_run_definition(run, definition) is Err(_) {
    return Err(ForeignRun)
  }
  guard client_compiled_run_serialization(run) is Some(component) &&
    physical_equal(component.owner, run.owner) else {
    return Err(MissingComponent)
  }
  guard parse_plan_identity_value(
      @publication.run_evidence_value_json(input),
      16384,
      256,
      16,
    )
    is Some(input_body) &&
    parse_plan_identity_value(
      @publication.run_evidence_value_json(derivation),
      16384,
      256,
      16,
    )
    is Some(derivation_body) &&
    @canonical.object_field(input_body, "task_ordinal")
    is Some(@canonical.Number(task)) &&
    task == component.task.to_double() &&
    @canonical.object_field(input_body, "step_ordinal")
    is Some(@canonical.Number(step)) &&
    step == component.step.to_double() &&
    infer_scope_string(input_body, "input_fragment_cid") ==
    Some(component.input.logical_cid) else {
    return Err(ForeignInput)
  }
  if infer_scope_string(input_body, "effective_data_policy_cid") !=
    Some(@publication.captured_effect_dependency_body_cid(component.policy)) {
    return Err(PolicyMismatch)
  }
  guard @canonical.object_field(input_body, "row_count")
    is Some(@canonical.Number(rows)) &&
    rows >= 0 &&
    rows <= component.max_rows.to_double() &&
    @canonical.object_field(derivation_body, "byte_count")
    is Some(@canonical.Number(bytes)) &&
    bytes >= 0 &&
    bytes <= component.max_bytes.to_double() else {
    return Err(QuantityMismatch)
  }
  @publication.readmit_generated_content_observation(
    run.template,
    @publication.publication_contract_identity(definition),
    component.output.node_id,
    component.output.logical_cid,
    expected_generation_cid,
    input,
    derivation,
    generation,
    candidate,
    content,
  ).map_err(issue => Evidence(issue))
}
