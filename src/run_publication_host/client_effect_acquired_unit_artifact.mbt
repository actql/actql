///|
/// Produce a dependency Artifact before the checked consumer executes. The
/// source observation, local invocation, Result export and Run admission keep
/// their existing Owners. This custody cannot stand in for final Effect inputs.
pub fn issue_acquired_client_effect_unit_result_artifact(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectLocalUnitInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  source : ClientEffectAcquiredEvidence,
  definition : ClientEffectLocalResultDefinition,
  receipt : @execution.CompletedRelationExportReceipt,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  run_invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientEffectLocalResultArtifact,
  ClientEffectLocalResultArtifactIssue,
] {
  let result = @strategy.captured_effect_local_result_export_result(exported)
  if !physical_equal(source.owner, owner) ||
    !@strategy.captured_effect_local_unit_inputs_match_computation(
      inputs,
      owner.graph,
    ) ||
    (
      !@strategy.captured_effect_local_unit_result_matches_source(
        inputs,
        result,
        source.identity,
      ) &&
      !(client_effect_computed_result_matches_acquired_unit(
        owner, source, exported,
      ) &&
      @strategy.captured_effect_local_unit_acquired_source_matches(
        inputs,
        source.identity,
      ))
    ) {
    return Err(ForeignOwner)
  }
  if !@strategy.captured_effect_local_unit_result_export_matches_receipt(
      inputs, exported, receipt,
    ) {
    return Err(ForeignExport)
  }
  build_client_effect_acquired_result_artifact(
    AcquiredUnit(inputs),
    owner,
    @strategy.captured_effect_local_result_borrow(result),
    source,
    definition,
    receipt,
    admission,
    run_definition,
    run_invocation,
    observation,
    max_bytes,
    max_nodes,
    max_depth,
  )
}
