///|
/// Complete provenance from the SAME live Model output and accepted issuer.
/// The enclosing capture operation backs and retains the returned metadata;
/// neither this projection nor an individual Source contribution grants apply.
pub fn issue_original_local_model_acquired_evidence(
  value : LocalModelObservation,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  imports? : @publication_host.ClientEffectImportedEvidence? = None,
  source_originals? : Array[@publication_host.ClientEffectAcquiredEvidence] = [],
) -> Result[
  @publication_host.ClientEffectModelAcquiredEvidence,
  @publication_host.ClientEffectAcquiredEvidenceIssue,
] {
  guard original_local_model_observation_current(value.held, value.issued) &&
    value.held.owner.call_scope is Some(scope) else {
    return Err(Invocation(ForeignCapturedInput))
  }
  let result = match
    (
      value.held.owner.saved_call_scope,
      value.held.owner.composed_sources,
      imports,
    ) {
    (Some(saved), None, Some(original)) =>
      @publication_host.issue_restored_model_client_effect_imported_evidence(
        value.issued.state.compiled,
        scope,
        saved,
        value.body,
        retention,
        max_bytes,
        max_nodes,
        max_depth,
        original,
        source_originals,
      )
    (None, Some(sources), _) =>
      @publication_host.issue_single_model_client_effect_acquired_evidence(
        value.issued.state.compiled,
        scope,
        value.body,
        sources,
        retention,
        max_bytes,
        max_nodes,
        max_depth,
        imports~,
      )
    _ => Err(Invocation(ForeignCapturedInput))
  }
  if !original_local_model_observation_current(value.held, value.issued) {
    return Err(Invocation(ForeignCapturedInput))
  }
  result
}

///|
/// Bind the exported Result to this exact original completed Model output.
/// Run observation/Invocation come from the retained issuer, not caller wire.
/// Saved restoration remains a separate authenticated original entrance.
pub fn issue_original_local_model_effect_artifact(
  value : LocalModelObservation,
  materials : @publication_host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  acquired : @publication_host.ClientEffectModelAcquiredEvidence,
  definition : @publication_host.ClientEffectLocalResultDefinition,
  receipt : @relation.CompletedRelationExportReceipt,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalResultArtifact,
  @publication_host.ClientEffectLocalResultArtifactIssue,
] {
  guard value.issued.state.observation is Some(observation) &&
    value.issued.state.invocation is Some(invocation) else {
    return Err(ForeignOwner)
  }
  issue_original_local_model_effect_artifact_with_context(
    value,
    materials.prepared,
    inputs,
    exported,
    acquired,
    definition,
    receipt,
    @publication_host.client_effect_allowed_run_admission(materials.allowed),
    materials.run_definition,
    invocation,
    observation,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// The installed publisher already retains these original typed contracts.
/// Require the SAME complete issuer context; do not reconstruct materials or
/// accept a Source-only invocation in place of the original Model invocation.
/// Existing artifact admission still binds the actual output/Result/current
/// custody and full publication tuple. This grants no Store/Effect authority.
pub fn issue_original_local_model_effect_artifact_with_context(
  value : LocalModelObservation,
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  acquired : @publication_host.ClientEffectModelAcquiredEvidence,
  definition : @publication_host.ClientEffectLocalResultDefinition,
  receipt : @relation.CompletedRelationExportReceipt,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalResultArtifact,
  @publication_host.ClientEffectLocalResultArtifactIssue,
] {
  guard original_local_model_observation_current(value.held, value.issued) &&
    value.held.owner.call_scope is Some(scope) &&
    @publication_host.client_effect_model_acquired_matches(
      acquired,
      value.issued.state.compiled,
      scope,
      value.body,
    ) &&
    @publication.publication_contract_identity(run_definition) ==
    @publication.publication_contract_identity(value.issued.state.definition) &&
    value.issued.state.observation is Some(original_observation) &&
    physical_equal(observation, original_observation) &&
    value.issued.state.invocation is Some(original_invocation) &&
    physical_equal(invocation, original_invocation) else {
    return Err(ForeignOwner)
  }
  let result = @publication_host.issue_model_client_effect_local_result_artifact(
    owner,
    inputs,
    exported,
    acquired,
    value.held.output,
    definition,
    receipt,
    admission,
    run_definition,
    invocation,
    observation,
    max_bytes,
    max_nodes,
    max_depth,
  )
  if !original_local_model_observation_current(value.held, value.issued) {
    return Err(ForeignOwner)
  }
  result
}
