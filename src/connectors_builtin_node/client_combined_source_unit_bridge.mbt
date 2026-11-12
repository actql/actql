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
  let (direct, originals) = match
    client_program_installed_effect_source_originals(
      plan,
      prepared,
      request,
      captures.length(),
      identities.length(),
      sources.length(),
      inputs.length(),
      max_nodes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
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

///|
/// Both publication phases select the same installed originals and coverage.
fn client_program_installed_effect_source_originals(
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  capture_count : Int,
  identity_count : Int,
  source_count : Int,
  input_count : Int,
  max_nodes : Int,
) -> Result[
  (
    @publication_host.ClientDirectAcquisitionOccurrences,
    Array[@publication_host.ClientDirectSourceOriginal],
  ),
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
    capture_count != count ||
    identity_count != count ||
    source_count != count ||
    input_count != count {
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
  Ok((direct, originals))
}

///|
/// Source-only Unit custody, without claiming unfinished Model observations.
#export_name("clientProgramPrepareInstalledEffectSourceUnitInputs")
pub fn client_program_prepare_installed_effect_source_unit_inputs(
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
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectSourceUnitInputs,
  @publication.RunEvidenceValueIssue,
] {
  let (direct, originals) = match
    client_program_installed_effect_source_originals(
      plan,
      prepared,
      request,
      captures.length(),
      identities.length(),
      sources.length(),
      inputs.length(),
      max_nodes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @publication_host.prepare_client_effect_source_unit_inputs(
    prepared, compilation, admission, definition, direct, captures, identities, originals,
    sources, inputs, authority_scope_cid, data_policy_cid, max_bytes, max_nodes,
    max_depth,
  )
}

///|
#export_name("clientProgramPreparePreconsumerEffectSourceUnit")
pub fn client_program_prepare_preconsumer_effect_source_unit(
  inputs : @publication_host.ClientEffectSourceUnitInputs,
  unit : Int,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectCombinedSourceUnit,
  @publication_host.ClientEffectAcquiredEvidenceIssue,
] {
  @publication_host.prepare_client_effect_source_unit(
    inputs, unit, retention, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramPrepareInstalledEffectModelSourceUnit")
pub fn client_program_prepare_installed_effect_model_source_unit(
  run : @client_local_host.ClientInstalledManagedRun,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  inputs : @publication_host.ClientEffectSourceUnitInputs,
  unit : Int,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectCombinedSourceUnit,
  @client_local_host.ClientEffectUnitPreparationIssue,
] {
  @client_local_host.prepare_installed_effect_model_source_unit(
    run, plan, request, inputs, unit, retention, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramPrepareInstalledEffectModelSourceUnitCatalog")
pub fn client_program_prepare_installed_effect_model_source_unit_catalog(
  run : @client_local_host.ClientInstalledManagedRun,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  inputs : @publication_host.ClientEffectSourceUnitInputs,
  unit : @publication_host.ClientEffectCombinedSourceUnit,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  Array[(String, String, String)],
  @client_local_host.ClientEffectUnitPreparationIssue,
] {
  @client_local_host.prepare_installed_effect_model_source_unit_catalog(
    run, plan, request, inputs, unit, max_bytes, max_nodes, max_depth,
  )
}
