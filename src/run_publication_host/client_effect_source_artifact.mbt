///|
pub(all) enum ClientEffectSourceArtifactIssue {
  Unavailable
  ForeignInput
  ForeignRun
  ForeignInvocation
  ForeignRetention
  Artifact(@publication.EffectSourceArtifactIssue)
}

///|
/// Issue private Source facts from the exact completed local Result owner.
/// The original Run Invocation and retention cannot be replaced by a later
/// caller proposal. This is semantic evidence; durable Store custody and
/// current write authorization remain independent obligations.
pub fn issue_client_effect_local_source_artifact(
  materials : ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  artifact : ClientEffectLocalResultArtifact,
  invocation : @publication.PublicationContract,
  retention : @publication.PublicationContract,
  source_binding_cid : String,
  store_authority_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.PublicationContract, ClientEffectSourceArtifactIssue] {
  let owner = materials.prepared
  if !physical_equal(materials.compilation.owner, owner) ||
    !physical_equal(materials.compilation, materials.allowed.compilation) ||
    !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) ||
    !client_effect_local_artifact_matches_inputs(artifact, inputs) ||
    !client_effect_local_artifact_matches_member(artifact, inputs, member_index) {
    return Err(ForeignInput)
  }
  let run = @publication.publication_contract_identity(materials.run_definition)
  if @strategy.captured_effect_inputs_run_definition_cid(inputs) != Some(run) ||
    client_effect_local_artifact_run_definition_cid(artifact) != Some(run) {
    return Err(ForeignRun)
  }
  if client_effect_local_artifact_run_invocation_cid(artifact) !=
    Some(@publication.publication_contract_identity(invocation)) {
    return Err(ForeignInvocation)
  }
  if @publication.publication_contract_identity(artifact.retention) !=
    @publication.publication_contract_identity(retention) {
    return Err(ForeignRetention)
  }
  guard artifact.source is ResultSource(_, definition) &&
    @strategy.captured_effect_input_at(inputs, member_index) is Some(input) else {
    return Err(ForeignInput)
  }
  let unit = @strategy.captured_effect_input_stage(input)
  let name = @execution.managed_result_occurrence_name(
    @strategy.captured_effect_input_occurrence(input),
  )
  if !client_effect_local_result_definition_matches(
      definition, owner, unit, name,
    ) ||
    !client_effect_local_invocation_matches(artifact.invocation, owner, unit) {
    return Err(ForeignInput)
  }
  let receipt = artifact.export_receipt
  @publication.issue_effect_source_artifact(
    invocation,
    retention,
    name,
    source_binding_cid,
    store_authority_cid,
    @execution.logical_relation_cid(
      @execution.completed_relation_export_identity(receipt),
    ),
    @execution.relation_schema_cid(
      @execution.completed_relation_export_schema_identity(receipt),
    ),
    @execution.completed_relation_export_measurement(receipt).row_count,
    max_bytes,
    max_nodes,
    max_depth,
  ).map_err(issue => Artifact(issue))
}
