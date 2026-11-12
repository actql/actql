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

///|
#export_name("clientProgramPinInstalledEffectModelUnitResults")
pub fn client_program_pin_installed_effect_model_unit_results(
  run : @client_local_host.ClientInstalledManagedRun,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  captured : @strategy.CapturedEffectRunDAG,
  unit : Int,
) -> Result[
  @strategy.CapturedEffectLocalUnitInputs,
  @client_local_host.ClientEffectUnitPreparationIssue,
] {
  @client_local_host.pin_installed_effect_model_unit_results(
    run, plan, request, captured, unit,
  )
}

///|
#export_name("clientProgramPrepareInstalledEffectModelUnitResultExport")
pub fn client_program_prepare_installed_effect_model_unit_result_export(
  run : @client_local_host.ClientInstalledManagedRun,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  captured : @strategy.CapturedEffectRunDAG,
  inputs : @strategy.CapturedEffectLocalUnitInputs,
  index : Int,
) -> Result[
  @strategy.CapturedEffectLocalResultExport,
  @client_local_host.ClientEffectUnitPreparationIssue,
] {
  @client_local_host.prepare_installed_effect_model_unit_result_export(
    run, plan, request, captured, inputs, index,
  )
}

///|
/// Bounded technical DATA from the original returned export Result only.
/// No compiler constructor names, body fields or current checks cross this port.
#export_name("clientProgramEffectModelUnitResultExportIssueKind")
pub fn client_program_effect_model_unit_result_export_issue_kind(
  result : Result[
    @strategy.CapturedEffectLocalResultExport,
    @client_local_host.ClientEffectUnitPreparationIssue,
  ],
) -> String? {
  match result {
    Ok(_) => None
    Err(Run(_)) => Some("run")
    Err(Evidence(_)) => Some("evidence")
    Err(Pin(_)) => Some("pin")
    Err(Artifact(_)) => Some("artifact")
    Err(Manifest(_)) => Some("manifest")
    Err(Export(issue)) =>
      Some(
        match issue {
          MissingResult => "export.missing_result"
          ForeignOutput => "export.foreign_output"
          Export(issue) =>
            match issue {
              Unavailable => "export.completed.unavailable"
              NotCellRepresentation =>
                "export.completed.not_cell_representation"
              InvalidTarget => "export.completed.invalid_target"
              NotFinished => "export.completed.not_finished"
              Closed => "export.completed.closed"
              ForeignMaterial => "export.completed.foreign_material"
              Admission(_) => "export.completed.admission"
              Wire(_) => "export.completed.wire"
              Schema(_) => "export.completed.schema"
              ResultView(_) => "export.completed.result_view"
              CanonicalRow => "export.completed.canonical_row"
            }
        },
      )
  }
}

///|
#export_name("clientProgramEffectModelUnitResultCount")
pub fn client_program_effect_model_unit_result_count(
  inputs : @strategy.CapturedEffectLocalUnitInputs,
) -> Int {
  @strategy.captured_effect_local_unit_result_count(inputs)
}

///|
#export_name("clientProgramReleaseEffectModelUnitResults")
pub fn client_program_release_effect_model_unit_results(
  inputs : @strategy.CapturedEffectLocalUnitInputs,
) -> Bool {
  @strategy.release_captured_effect_local_unit_inputs(inputs)
}

///|
#export_name("clientProgramPrepareInstalledEffectModelSourceUnitArtifact")
pub fn client_program_prepare_installed_effect_model_source_unit_artifact(
  run : @client_local_host.ClientInstalledManagedRun,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  inputs : @strategy.CapturedEffectLocalUnitInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  combined : @publication_host.ClientEffectCombinedSourceUnit,
  receipt : @execution.CompletedRelationExportReceipt,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalResultArtifact,
  @client_local_host.ClientEffectUnitPreparationIssue,
] {
  @client_local_host.prepare_installed_effect_model_source_unit_artifact(
    run, plan, request, inputs, exported, combined, receipt, admission, definition,
    max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramPrepareInstalledEffectModelUnitManifest")
pub fn client_program_prepare_installed_effect_model_unit_manifest(
  run : @client_local_host.ClientInstalledManagedRun,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  invocation : @publication_host.ClientEffectLocalInvocation,
  artifacts : Array[@publication_host.ClientEffectLocalResultArtifact],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalManifest,
  @client_local_host.ClientEffectUnitPreparationIssue,
] {
  @client_local_host.prepare_installed_effect_model_unit_manifest(
    run, plan, request, invocation, artifacts, max_bytes, max_nodes, max_depth,
  )
}

///|
/// The original Named Result exporter already owns projection/order and
/// bounded row encoding. No canonical-row reparse or Store write is needed
/// merely to establish this upstream semantic Artifact's exact receipt.
#export_name("clientProgramEffectModelUnitExportReceipt")
pub fn client_program_effect_model_unit_export_receipt(
  exported : @strategy.CapturedEffectLocalResultExport,
) -> Result[
  @execution.CompletedRelationExportReceipt,
  @execution.CompletedExportIssue,
] {
  let preparation = @strategy.captured_effect_local_result_export_preparation(
    exported,
  )
  while true {
    match
      @execution.advance_completed_result_relation_export(preparation, 256) {
      Ok((true, _)) => break
      Ok((false, _)) => ()
      Err(issue) => return Err(issue)
    }
  }
  let stream = match
    @execution.finish_completed_result_relation_export_preparation(preparation) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  while true {
    match @execution.next_completed_output_export(stream) {
      Ok(Some(_)) => ()
      Ok(None) => break
      Err(issue) => {
        @execution.cancel_completed_output_export(stream)
        return Err(issue)
      }
    }
  }
  @execution.finish_completed_relation_export(stream).map(value => value.0)
}

///|
#export_name("clientProgramEffectModelUnitResultName")
pub fn client_program_effect_model_unit_result_name(
  inputs : @strategy.CapturedEffectLocalUnitInputs,
  index : Int,
) -> String? {
  @strategy.captured_effect_local_unit_result_at(inputs, index).map(result => {
    @execution.managed_result_occurrence_name(
      @strategy.captured_any_result_borrow_occurrence(
        @strategy.captured_effect_local_result_borrow(result),
      ),
    )
  })
}

///|
#export_name("clientProgramBindOriginalEffectUnitArtifactRunContext")
pub fn client_program_bind_original_effect_unit_artifact_run_context(
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  artifact : @publication_host.ClientEffectLocalResultArtifact,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
) -> Result[Unit, @publication_host.ClientEffectLocalResultArtifactIssue] {
  @publication_host.bind_client_effect_unit_artifact_run_context(
    owner, inputs, artifact, admission, definition, invocation, observation,
  )
}

///|
#export_name("clientProgramOriginalEffectUnitArtifactDefinition")
pub fn client_program_original_effect_unit_artifact_definition(
  artifact : @publication_host.ClientEffectLocalResultArtifact,
) -> Result[
  @publication_host.ClientEffectLocalResultDefinition,
  @publication_host.ClientEffectLocalResultArtifactIssue,
] {
  match
    @publication_host.client_effect_unit_artifact_original_definition(artifact) {
    Some(value) => Ok(value)
    None => Err(ForeignDefinition)
  }
}

///|
#export_name("clientProgramCheckOriginalEffectUnitArtifactExport")
pub fn client_program_check_original_effect_unit_artifact_export(
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  artifact : @publication_host.ClientEffectLocalResultArtifact,
  exported : @strategy.CapturedEffectLocalResultExport,
  receipt : @execution.CompletedRelationExportReceipt,
) -> Result[Unit, @publication_host.ClientEffectLocalResultArtifactIssue] {
  @publication_host.check_client_effect_unit_artifact_export(
    owner, inputs, artifact, exported, receipt,
  )
}

///|
#export_name("clientProgramOriginalEffectUnitManifestMatches")
pub fn client_program_original_effect_unit_manifest_matches(
  manifest : @publication_host.ClientEffectLocalManifest,
  owner : @publication_host.PreparedClientEffectComputation,
  invocation : @publication_host.ClientEffectLocalInvocation,
  artifacts : Array[@publication_host.ClientEffectLocalResultArtifact],
) -> Bool {
  @publication_host.client_effect_local_manifest_matches(
    manifest, owner, invocation, artifacts,
  )
}
