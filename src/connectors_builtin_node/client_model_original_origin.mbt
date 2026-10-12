///|
// Read only the original checked issuer's field, before its resources are
// parked. The installing caller obtains storage evidence from the same actual
// opaque Store binding; a caller CID is not that custody or a restore grant.
#export_name("clientProgramInferOriginalResourceOriginField")
pub fn client_program_infer_original_resource_origin_field(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : @publication_host.ClientInferPlanGraph,
  layout : @publication_host.ClientNodeModelPreparationLayout?,
  installation : @check_environment.ModelResponseProfileInstallation,
  runtime_artifact_cid : String,
  layout_artifact_cid : String,
  probability : @check_environment.DecisionProbabilityProfile?,
  storage : @publication.RunEvidenceValue,
  field : String,
) -> Result[String, @publication_host.ClientModelOriginalOriginIssue] {
  @publication_host.client_model_original_origin_field(
    scope, compiled, definition, graph, layout, installation, runtime_artifact_cid,
    layout_artifact_cid, probability, storage, field,
  )
}
