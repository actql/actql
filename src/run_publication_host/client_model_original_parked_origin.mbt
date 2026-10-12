///|
// Recheck the checked eleven original fields under the exact existing parked
// Scope. Do not make initial inventory available while parked. This proves
// neither Model quiescence nor Store/journal custody, restoration or send.
pub fn check_client_model_original_parked_origin(
  park : ClientModelResourcePark,
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
  guard client_model_resource_park_current(
      park, scope, compiled, definition, plan,
    )
    is Some(_) else {
    return Err(Unavailable)
  }
  check_client_model_original_origin_fields(
    scope, compiled, definition, plan, document, layout, installation, runtime_artifact_cid,
    layout_artifact_cid, probability,
  )
}

///|
// The caller obtains storage through the SAME actual installed Evidence port
// and its exact opaque handle after rechecking that physical Store. A copied
// sealed value can match this DATA-only guard and is not custody proof. Repeat
// the exact installed journal/Model/Store fences separately before COMMIT.
pub fn check_client_model_original_parked_storage_origin(
  park : ClientModelResourcePark,
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
  storage : @publication.RunEvidenceValue,
) -> Result[Unit, ClientModelOriginalOriginIssue] {
  match
    check_client_model_original_parked_origin(
      park, scope, compiled, definition, plan, document, layout, installation, runtime_artifact_cid,
      layout_artifact_cid, probability,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  check_client_model_original_storage_origin_field(document, storage)
}
