///|
pub(all) enum ClientModelOriginalOriginIssue {
  Unavailable
  ForeignRun
  OriginMismatch(String)
  Layout(ClientModelPreparationLayoutIssue)
} derive(Eq, Debug)

///|
// Check only the eleven checked Run/plan/selected-layout origin fields. This
// deliberately does NOT admit storage_binding_cid, Store ACK, current cut or
// restored resources. Those require the original physical custody issuer and
// journal fences, not a caller/configuration CID used as both expected/actual.
// Scope bootstrap must cover the existing getter/validation workspace; this
// read-only guard neither adds retained control nor changes usage/serial/phase.
pub fn check_client_model_original_checked_origin(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  document : @publication.ModelOriginalResourceDocument,
  layout : ClientNodeModelPreparationLayout?,
  installation : @environment.ModelResponseProfileInstallation,
  runtime_artifact_cid : String,
  layout_artifact_cid : String,
  probability : @environment.DecisionProbabilityProfile?,
) -> Result[Unit, ClientModelOriginalOriginIssue] {
  if !@resources.original_ledger_inventory_available(scope.identity) {
    return Err(Unavailable)
  }
  check_client_model_original_origin_fields(
    scope, compiled, definition, plan, document, layout, installation, runtime_artifact_cid,
    layout_artifact_cid, probability,
  )
}

///|
// Shared data validation only. Every public entry must establish its own
// original lifecycle first: initial available inventory or exact live park.
fn check_client_model_original_origin_fields(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  document : @publication.ModelOriginalResourceDocument,
  layout : ClientNodeModelPreparationLayout?,
  installation : @environment.ModelResponseProfileInstallation,
  runtime_artifact_cid : String,
  layout_artifact_cid : String,
  probability : @environment.DecisionProbabilityProfile?,
) -> Result[Unit, ClientModelOriginalOriginIssue] {
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
  let run_id = match @publication.run_definition_run_id(definition) {
    Ok(value) => value
    Err(_) => return Err(ForeignRun)
  }
  let identity = prepared_client_identity(plan.owner)
  // Each expected value originates independently from the original checked
  // Owner. Never read an expected value from document.origin or a response.
  if @publication.model_original_resource_origin_field(document, "run_id") !=
    Some(run_id) {
    return Err(OriginMismatch("run_id"))
  }
  if @publication.model_original_resource_origin_field(
      document, "run_definition_cid",
    ) !=
    Some(scope.origin.definition_cid) {
    return Err(OriginMismatch("run_definition_cid"))
  }
  if @publication.model_original_resource_origin_field(
      document, "prepared_invocation_cid",
    ) !=
    Some(
      @publication.run_evidence_value_identity(
        @publication.run_publication_prepared(compiled.admission),
      ),
    ) {
    return Err(OriginMismatch("prepared_invocation_cid"))
  }
  if @publication.model_original_resource_origin_field(
      document, "host_policy_cid",
    ) !=
    Some(scope.origin.host_policy_cid) {
    return Err(OriginMismatch("host_policy_cid"))
  }
  if @publication.model_original_resource_origin_field(
      document, "execution_context_cid",
    ) !=
    Some(scope.origin.execution_context_cid) {
    return Err(OriginMismatch("execution_context_cid"))
  }
  if @publication.model_original_resource_origin_field(
      document, "program_definition_cid",
    ) !=
    Some(identity.program_definition_cid) {
    return Err(OriginMismatch("program_definition_cid"))
  }
  if @publication.model_original_resource_origin_field(
      document, "parameter_values_cid",
    ) !=
    Some(identity.parameter_values_cid) {
    return Err(OriginMismatch("parameter_values_cid"))
  }
  if @publication.model_original_resource_origin_field(document, "barrier_cid") !=
    Some(plan.barrier_cid) {
    return Err(OriginMismatch("barrier_cid"))
  }
  if @publication.model_original_resource_origin_field(
      document, "runtime_artifact_cid",
    ) !=
    Some(layout.runtime_artifact_cid) {
    return Err(OriginMismatch("runtime_artifact_cid"))
  }
  if @publication.model_original_resource_origin_field(
      document, "layout_artifact_cid",
    ) !=
    Some(layout.layout_artifact_cid) {
    return Err(OriginMismatch("layout_artifact_cid"))
  }
  if @publication.model_original_resource_origin_field(
      document, "response_profile_cid",
    ) !=
    Some(@environment.model_response_profile_identity(layout.response_profile)) {
    return Err(OriginMismatch("response_profile_cid"))
  }
  Ok(())
}
