///|
/// Same installed Plan/Request originals; no new acquisition or completed output.
#export_name("clientProgramPrepareInstalledEffectDirectSourcesPublication")
pub fn client_program_prepare_installed_effect_direct_sources_publication(
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  compilation : @publication_host.ClientEffectCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  captures : Array[@query.CapturedInputSource],
  identities : Array[@query.CapturedSourceRelationIdentity],
  sources : Array[@publication.RunEvidenceValue],
  inputs : Array[@publication.RunEvidenceValue],
  authority_scope_cid : String,
  data_policy_cid : String,
  capture_started_at : String,
  capture_completed_at : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectDirectSourcesPublication,
  @publication.RunEvidenceValueIssue,
] {
  let direct = match
    @client_local_host.prepared_installed_effect_source_occurrences(
      plan, prepared, request,
    ) {
    Ok(Some(value)) => value
    _ => return Err(@publication.RunEvidenceReferenceMismatch("effect_run"))
  }
  let count = @publication_host.client_direct_acquisition_occurrence_count(
    direct,
  )
  if count < 1 ||
    count > max_nodes ||
    captures.length() != count ||
    identities.length() != count ||
    sources.length() != count ||
    inputs.length() != count {
    return Err(@publication.RunEvidenceReferenceMismatch("source_coverage"))
  }
  let originals : Array[@publication_host.ClientDirectSourceOriginal] = []
  for slot in 0..<count {
    match
      @client_local_host.prepared_installed_effect_managed_whole_source(
        plan, slot,
      ) {
      Ok((acquisition, _, _)) =>
        originals.push(@publication_host.WholeSourceOriginal(acquisition))
      Err(_) =>
        match
          @client_local_host.prepared_installed_effect_managed_query_requirement(
            plan, slot,
          ) {
          Ok(requirement) =>
            originals.push(@publication_host.QuerySourceOriginal(requirement))
          Err(_) =>
            return Err(@publication.RunEvidenceReferenceMismatch("source_task"))
        }
    }
  }
  @publication_host.prepare_client_effect_direct_sources_publication(
    prepared, compilation, admission, definition, direct, captures, identities, originals,
    sources, inputs, authority_scope_cid, data_policy_cid, capture_started_at, capture_completed_at,
    max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramEffectDirectSourcesPublicationInvocation")
pub fn client_program_effect_direct_sources_publication_invocation(
  value : @publication_host.ClientEffectDirectSourcesPublication,
) -> @publication.PublicationContract {
  @publication_host.client_effect_direct_sources_publication_invocation(value)
}

///|
#export_name("clientProgramEffectDirectSourcesPublicationObservation")
pub fn client_program_effect_direct_sources_publication_observation(
  value : @publication_host.ClientEffectDirectSourcesPublication,
) -> @publication.RunEvidenceValue {
  @publication_host.client_effect_direct_sources_publication_observation(value)
}

///|
#export_name("clientProgramCombinedEffectSourceUnitInvocation")
pub fn client_program_combined_effect_source_unit_invocation(
  value : @publication_host.ClientEffectCombinedSourceUnit,
) -> @publication_host.ClientEffectLocalInvocation {
  @publication_host.client_effect_combined_source_unit_invocation(value)
}

///|
#export_name("clientProgramCombinedEffectSourceUnitDependencyBodies")
pub fn client_program_combined_effect_source_unit_dependency_bodies(
  value : @publication_host.ClientEffectCombinedSourceUnit,
) -> Array[(String, String, String)] {
  @publication_host.client_effect_combined_source_unit_dependency_bodies(value)
}

///|
#export_name("clientProgramPrepareCombinedEffectSourceUnit")
pub fn client_program_prepare_combined_effect_source_unit(
  publication : @publication_host.ClientEffectDirectSourcesPublication,
  unit : Int,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectCombinedSourceUnit,
  @publication_host.ClientEffectAcquiredEvidenceIssue,
] {
  @publication_host.prepare_client_effect_combined_source_unit(
    publication, unit, retention, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramCombinedEffectSourceUnitCatalogBodies")
pub fn client_program_combined_effect_source_unit_catalog_bodies(
  value : @publication_host.ClientEffectCombinedSourceUnit,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  Array[(String, String, String)],
  @publication_host.ClientEffectAcquiredEvidenceIssue,
] {
  @publication_host.client_effect_combined_source_unit_catalog_bodies(
    value, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramIssueCombinedSourceEffectLocalResultArtifact")
pub fn client_program_issue_combined_source_effect_local_result_artifact(
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  source : @publication_host.ClientEffectCombinedSourceUnit,
  definition : @publication_host.ClientEffectLocalResultDefinition,
  receipt : @execution.CompletedRelationExportReceipt,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  run_invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalResultArtifact,
  @publication_host.ClientEffectLocalResultArtifactIssue,
] {
  @publication_host.issue_combined_source_client_effect_local_result_artifact(
    owner, inputs, exported, source, definition, receipt, admission, run_definition,
    run_invocation, observation, max_bytes, max_nodes, max_depth,
  )
}
