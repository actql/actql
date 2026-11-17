///|
#export_name("clientProgramEffectKeyedDeclaredFileActivationRecord")
pub fn client_program_effect_keyed_declared_file_activation_record(
  activation : @publication_host.ClientKeyedNativeActivation,
  request : @publication_host.ClientRequestIdentity,
  original : @publication_host.ClientEffectKeyedOriginal,
  max_bytes : Int,
) -> Result[String, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.prepare_client_effect_keyed_declared_file_activation_record(
    activation, request, original, max_bytes,
  )
}

///|
#export_name("clientProgramEffectKeyedNativeActivationMatches")
pub fn client_program_effect_keyed_native_activation_matches(
  activation : @publication_host.ClientKeyedNativeActivation,
  request : @publication_host.ClientRequestIdentity,
  original : @publication_host.ClientEffectKeyedOriginal,
) -> Bool {
  @publication_host.client_effect_keyed_native_activation_matches(
    activation, request, original,
  )
}

///|
#export_name("clientProgramEffectKeyedDeclaredFilePageRecord")
pub fn client_program_effect_keyed_declared_file_page_record(
  page : @publication_host.ClientKeyedNativeCapturedPage,
  keyed_request : @publication_host.ClientKeyedRequest,
  request : @publication_host.ClientRequestIdentity,
  original : @publication_host.ClientEffectKeyedOriginal,
  max_bytes : Int,
) -> Result[String, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.prepare_client_effect_keyed_declared_file_page_record(
    page, keyed_request, request, original, max_bytes,
  )
}

///|
#export_name("clientProgramEffectKeyedNativeCapturedPageMatches")
pub fn client_program_effect_keyed_native_captured_page_matches(
  page : @publication_host.ClientKeyedNativeCapturedPage,
  keyed_request : @publication_host.ClientKeyedRequest,
  request : @publication_host.ClientRequestIdentity,
  original : @publication_host.ClientEffectKeyedOriginal,
) -> Bool {
  @publication_host.client_effect_keyed_native_captured_page_matches(
    page, keyed_request, request, original,
  )
}

///|
#export_name("clientProgramInstalledEffectKeyedOriginal")
pub fn client_program_installed_effect_keyed_original(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  @publication_host.ClientEffectKeyedOriginal,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.installed_effect_keyed_original(owner, prepared, request)
}

///|
#export_name("clientProgramInstalledEffectKeyedInputWorkLimit")
pub fn client_program_installed_effect_keyed_input_work_limit(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Result[Int, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.installed_effect_keyed_input_work_limit(
    owner, prepared, request,
  )
}

///|
#export_name("clientProgramStartInstalledEffectKeyedCaptureInput")
pub fn client_program_start_installed_effect_keyed_capture_input(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientEffectKeyedPlanGraph,
  keyed : @publication_host.ClientKeyedAcquisition,
  captures : Array[@client_row_source_host.RowSourceCapture],
  max_entries : Int,
  max_name_bytes : Int,
  max_bytes : Int,
  max_work : Int,
) -> Result[
  @publication_host.ClientKeyedLookupInput,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.start_installed_effect_keyed_capture_input(
    owner, prepared, request, compiled, definition, plan, keyed, captures, max_entries,
    max_name_bytes, max_bytes, max_work,
  )
}

///|
#export_name("clientProgramInstalledEffectKeyedLookupOriginal")
pub fn client_program_installed_effect_keyed_lookup_original(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  lookup : @publication_host.ClientKeyedLookupInput,
) -> Result[
  @publication_host.ClientKeyedLookupInput,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.installed_effect_keyed_lookup_original(
    owner, prepared, lookup,
  )
}

///|
#export_name("clientProgramKeyedLookupLeft")
pub fn client_program_keyed_lookup_left(
  lookup : @publication_host.ClientKeyedLookupInput,
) -> @publication_host.ClientKeyedLeftRead {
  @publication_host.client_keyed_lookup_left(lookup)
}

///|
#export_name("clientProgramEffectAllowedKeyedRun")
pub fn client_program_effect_allowed_keyed_run(
  allowed : @publication_host.ClientEffectAllowedRun,
  plan : @publication_host.ClientEffectKeyedPlanGraph,
  definition : @publication.PublicationContract,
) -> Result[
  @publication_host.ClientCompiledRun,
  @publication_host.ClientCompiledRunIssue,
] {
  @publication_host.client_effect_allowed_keyed_run(allowed, plan, definition)
}

///|
#export_name("clientProgramEffectKeyedPlanGraphIsGeneric")
pub fn client_program_effect_keyed_plan_graph_is_generic(
  plan : @publication_host.ClientEffectKeyedPlanGraph,
) -> Bool {
  @publication_host.client_effect_keyed_plan_graph_is_generic(plan)
}

///|
#export_name("clientProgramEffectSingleKeyedAcquisition")
pub fn client_program_effect_single_keyed_acquisition(
  prepared : @publication_host.PreparedClientEffectComputation,
) -> Result[
  @publication_host.ClientKeyedAcquisition?,
  @publication_host.ClientKeyedAcquisitionIssue,
] {
  @publication_host.select_client_effect_single_keyed_acquisition(prepared)
}

///|
#export_name("clientProgramPrepareRequestEffectKeyedPlan")
pub fn client_program_prepare_request_effect_keyed_plan(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  keyed : @publication_host.ClientKeyedAcquisition,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
  declarations : Array[@client_row_source_host.RowDeclaration],
) -> Result[
  @publication_host.ClientEffectKeyedPlanGraph,
  @client_local_host.ClientRequestProgramPlanIssue,
] {
  @client_local_host.prepare_request_effect_keyed_plan(
    parent, input, keyed, contracts, declarations,
  )
}

///|
#export_name("clientProgramPrepareRequestEffectKeyedOriginal")
pub fn client_program_prepare_request_effect_keyed_original(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  compilation : @publication_host.ClientEffectCompilation,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  keyed_plan : @publication_host.ClientEffectKeyedPlanGraph,
  keyed : @publication_host.ClientKeyedAcquisition,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.prepare_request_effect_keyed_original(
    parent, input, plan, compilation, compiled, definition, keyed_plan, keyed,
  )
}

///|
#export_name("clientProgramInstalledManagedEffectKeyedSourceRead")
pub fn client_program_installed_managed_effect_keyed_source_read(
  value : @client_local_host.ClientInstalledManagedRun,
  keyed : @publication_host.ClientKeyedAcquisition,
  request : @publication_host.ClientKeyedRequest,
  declaration : @client_row_source_host.RowDeclaration,
  max_page_bytes : Int,
  max_text_bytes : Int,
  max_work : Int,
) -> Result[
  @client_local_host.ClientInstalledKeyedSourceRead,
  @client_local_host.ClientInstalledSourceReadIssue,
] {
  @client_local_host.begin_installed_managed_effect_keyed_source_read(
    value,
    keyed,
    request,
    declaration,
    @client_local_host.installed_keyed_row_limits(
      max_page_bytes, max_text_bytes, max_work,
    ),
  )
}

///|
#export_name("clientProgramIssueInstalledEffectKeyedInvocation")
pub fn client_program_issue_installed_effect_keyed_invocation(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  host : ClientLocalEffectHost,
  compilation : @publication_host.ClientEffectCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  lookup : @publication_host.ClientKeyedLookupInput,
  started : String,
  completed : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @client_local_host.ClientClosedValuesPreparationIssue,
] {
  @client_local_host.issue_installed_effect_keyed_invocation(
    owner,
    prepared,
    request,
    plan,
    host.prepared,
    host.run,
    compilation,
    admission,
    definition,
    lookup,
    started,
    completed,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
#export_name("clientProgramPrepareInstalledEffectKeyedSourceUnit")
pub fn client_program_prepare_installed_effect_keyed_source_unit(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  host : ClientLocalEffectHost,
  lookup : @publication_host.ClientKeyedLookupInput,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectKeyedSourceUnit,
  @client_local_host.ClientEffectUnitPreparationIssue,
] {
  @client_local_host.prepare_installed_effect_keyed_source_unit(
    owner,
    prepared,
    request,
    plan,
    host.run,
    lookup,
    retention,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
#export_name("clientProgramEffectKeyedSourceUnitInvocation")
pub fn client_program_effect_keyed_source_unit_invocation(
  value : @publication_host.ClientEffectKeyedSourceUnit,
) -> @publication_host.ClientEffectLocalInvocation {
  @publication_host.client_effect_keyed_source_unit_invocation(value)
}

///|
#export_name("clientProgramEffectKeyedSourceUnitMetadataBodies")
pub fn client_program_effect_keyed_source_unit_metadata_bodies(
  value : @publication_host.ClientEffectKeyedSourceUnit,
) -> Array[(String, String, String)] {
  @publication_host.client_effect_keyed_source_unit_metadata_bodies(value)
}

///|
#export_name("clientProgramEffectKeyedCachedDependencyBodies")
pub fn client_program_effect_keyed_cached_dependency_bodies(
  original : @publication_host.ClientEffectKeyedOriginal,
  lookup : @publication_host.ClientKeyedLookupInput,
  retention : @publication.PublicationContract,
) -> Array[@publication.CapturedEffectDependencyBody]? {
  @publication_host.client_effect_keyed_cached_dependency_bodies(
    original, lookup, retention,
  )
}

///|
#export_name("clientProgramIssueInstalledKeyedSourceEffectLocalResultArtifact")
pub fn client_program_issue_installed_keyed_source_effect_local_result_artifact(
  parent : @client_local_host.ClientInstalledManagedRun,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  inputs : @strategy.CapturedEffectInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  source : @publication_host.ClientEffectKeyedSourceUnit,
  definition : @publication_host.ClientEffectLocalResultDefinition,
  receipt : @execution.CompletedRelationExportReceipt,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalResultArtifact,
  @client_local_host.ClientEffectUnitPreparationIssue,
] {
  @client_local_host.prepare_installed_effect_keyed_result_artifact(
    parent, plan, request, inputs, exported, source, definition, receipt, admission,
    run_definition, invocation, observation, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramEffectDependencyBodyKind")
pub fn client_program_effect_dependency_body_kind(
  body : @publication.CapturedEffectDependencyBody,
) -> String {
  @publication.captured_effect_dependency_body_kind(body)
}

///|
#export_name("clientProgramEffectDependencyBodyJson")
pub fn client_program_effect_dependency_body_json(
  body : @publication.CapturedEffectDependencyBody,
) -> String {
  @publication.captured_effect_dependency_body_json(body)
}

///|
#export_name("clientProgramEffectKeyedGenericSourceMetadata")
pub fn client_program_effect_keyed_generic_source_metadata(
  parent : @publication_host.ClientEffectKeyedOriginal,
  lookup : @publication_host.ClientKeyedLookupInput,
  identity : @query.CapturedSourceRelationIdentity,
  logical : @publication.RunEvidenceValue,
  observation : @publication.RunEvidenceValue,
  retention_contract : String,
  available_until : String,
  delete_by : String,
  metadata_delete_by : String,
  metadata_policy : String,
  clock_contract : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.PublicationContract,
  @publication_host.ClientKeyedRequestIssue,
] {
  @publication_host.prepare_client_effect_keyed_generic_source_metadata(
    parent, lookup, identity, logical, observation, retention_contract, available_until,
    delete_by, metadata_delete_by, metadata_policy, clock_contract, max_bytes, max_nodes,
    max_depth,
  )
}

///|
#export_name("clientProgramEffectKeyedGenericPublicationInput")
pub fn client_program_effect_keyed_generic_publication_input(
  parent : @publication_host.ClientEffectKeyedOriginal,
  lookup : @publication_host.ClientKeyedLookupInput,
  observed_at : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @execution.SuppliedRelationRead,
  @publication_host.ClientKeyedRequestIssue,
] {
  @publication_host.finish_client_effect_keyed_generic_publication_input(
    parent, lookup, observed_at, max_bytes, max_nodes, max_depth,
  )
}
