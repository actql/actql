///|
// Extend the checked eleven-field guard with the selected private Store's
// nominal binding evidence. The trusted physical caller must obtain `storage`
// through originalModelStorageBindingEvidence on the SAME live Evidence port
// and its exact opaque handle, after that port's actual Store recheck. A sealed
// RunEvidenceValue alone admits data, not physical custody. In particular,
// this Unit result does not admit a Store ACK, current cut, restore or send.
// The original bootstrap covers the existing getter/validation workspace;
// this guard creates no retained record, token, reservation or Ledger.
pub fn check_client_model_original_storage_origin(
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
    check_client_model_original_checked_origin(
      scope, compiled, definition, plan, document, layout, installation, runtime_artifact_cid,
      layout_artifact_cid, probability,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if @publication.run_evidence_value_name(storage) !=
    "model_original_storage_binding" ||
    @publication.model_original_resource_origin_field(
      document, "storage_binding_cid",
    ) !=
    Some(@publication.run_evidence_value_identity(storage)) {
    return Err(OriginMismatch("storage_binding_cid"))
  }
  Ok(())
}
