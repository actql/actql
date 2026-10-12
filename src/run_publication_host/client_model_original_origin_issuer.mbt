///|
// Borrow one original data field from the already funded checked Run/Host
// scope. No decoded document supplies an expected value, and no persistent
// binding/control, Ledger, reservation, restoration or send grant is issued.
// The original bootstrap covers each census/layout validation and the caller's
// complete Writer/value overlap before entry. Repeated calls do not establish
// a physical byte bound or a stable current cut.
// Storage must first come from the actual same-port opaque-handle getter; a
// sealed RunEvidenceValue alone cannot prove that physical custody obligation.
pub fn client_model_original_origin_field(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  layout : ClientNodeModelPreparationLayout?,
  installation : @environment.ModelResponseProfileInstallation,
  runtime_artifact_cid : String,
  layout_artifact_cid : String,
  probability : @environment.DecisionProbabilityProfile?,
  storage : @publication.RunEvidenceValue,
  field : String,
) -> Result[String, ClientModelOriginalOriginIssue] {
  if !@resources.original_ledger_inventory_available(scope.identity) {
    return Err(Unavailable)
  }
  if !client_model_origin_matches(scope.origin, compiled, definition, plan) {
    return Err(ForeignRun)
  }
  match
    check_client_node_model_preparation_layout(
      layout, plan, installation, runtime_artifact_cid, layout_artifact_cid, probability,
    ) {
    Err(issue) => return Err(Layout(issue))
    Ok(_) => ()
  }
  guard layout is Some(layout) else { return Err(Unavailable) }
  if @publication.run_evidence_value_name(storage) !=
    "model_original_storage_binding" {
    return Err(OriginMismatch("storage_binding_cid"))
  }
  // Closed field selection, preserving raw Run ID and existing identity bytes.
  // This does not normalize user data or derive identities from current config.
  match field {
    "run_id" =>
      @publication.run_definition_run_id(definition).map_err(_ => ForeignRun)
    "run_definition_cid" => Ok(scope.origin.definition_cid)
    "prepared_invocation_cid" =>
      Ok(
        @publication.run_evidence_value_identity(
          @publication.run_publication_prepared(compiled.admission),
        ),
      )
    "host_policy_cid" => Ok(scope.origin.host_policy_cid)
    "execution_context_cid" => Ok(scope.origin.execution_context_cid)
    "program_definition_cid" =>
      Ok(prepared_client_identity(plan.owner).program_definition_cid)
    "parameter_values_cid" =>
      Ok(prepared_client_identity(plan.owner).parameter_values_cid)
    "barrier_cid" => Ok(plan.barrier_cid)
    "runtime_artifact_cid" => Ok(layout.runtime_artifact_cid)
    "layout_artifact_cid" => Ok(layout.layout_artifact_cid)
    "response_profile_cid" =>
      Ok(@environment.model_response_profile_identity(layout.response_profile))
    "storage_binding_cid" =>
      Ok(@publication.run_evidence_value_identity(storage))
    _ => Err(OriginMismatch("origin_field"))
  }
}
