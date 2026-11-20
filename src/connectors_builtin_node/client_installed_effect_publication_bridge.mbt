///|
#export_name("clientProgramIssueInstalledEffectInitialRetention")
pub fn client_program_issue_installed_effect_initial_retention(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  retention_contract_cid : String,
  effective_data_policy_cid : String,
  available_until : String,
  delete_by : String,
  extension_ceiling_at : String,
  metadata_retention_policy_cid : String,
  metadata_delete_by : String,
  clock_contract_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.PublicationContract,
  @client_local_host.ClientEffectUnitPreparationIssue,
] {
  @client_local_host.issue_installed_effect_initial_retention(
    owner, prepared, request, plan, retention_contract_cid, effective_data_policy_cid,
    available_until, delete_by, extension_ceiling_at, metadata_retention_policy_cid,
    metadata_delete_by, clock_contract_cid, max_bytes, max_nodes, max_depth,
  )
}

///|
// Closed actual issuers on the same installed Effect host/Run. No generic
// callback/setter port, alternate owner, or CID-only publication witness.

///|
#export_name("clientProgramRebindInstalledEffectResultRetention")
pub fn client_program_rebind_installed_effect_result_retention(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  original : @publication.PublicationContract,
  policy : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.PublicationContract,
  @client_local_host.ClientEffectUnitPreparationIssue,
] {
  @client_local_host.rebind_installed_effect_result_retention(
    owner, prepared, request, plan, original, policy, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramIssueEffectSourceFreeInvocationOriginal")
pub fn client_program_issue_effect_source_free_invocation_original(
  compilation : @publication_host.ClientEffectCompilation,
  policy : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectSourceFreeInvocationOriginal,
  @publication.RunEvidenceValueIssue,
] {
  @publication_host.issue_client_effect_source_free_invocation_original(
    compilation, policy, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramEffectSourceFreeInvocationOriginalObservation")
pub fn client_program_effect_source_free_invocation_original_observation(
  value : @publication_host.ClientEffectSourceFreeInvocationOriginal,
) -> @publication.RunEvidenceValue {
  @publication_host.client_effect_source_free_invocation_original_observation(
    value,
  )
}

///|
#export_name("clientProgramEffectSourceFreeInvocationOriginalInvocation")
pub fn client_program_effect_source_free_invocation_original_invocation(
  value : @publication_host.ClientEffectSourceFreeInvocationOriginal,
) -> @publication.PublicationContract {
  @publication_host.client_effect_source_free_invocation_original_invocation(
    value,
  )
}

///|
#export_name("clientProgramBindInstalledEffectSourceFreeInvocation")
pub fn client_program_bind_installed_effect_source_free_invocation(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  host : ClientLocalEffectHost,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  issued : @publication_host.ClientEffectSourceFreeInvocationOriginal,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @client_local_host.ClientClosedValuesPreparationIssue,
] {
  let compilation = @publication_host.client_effect_source_free_invocation_original_compilation(
    issued,
  )
  @client_local_host.bind_installed_effect_source_free_invocation(
    owner,
    prepared,
    request,
    plan,
    host.prepared,
    host.run,
    compilation,
    admission,
    definition,
    issued,
  )
}

///|
#export_name("clientProgramIssueInstalledEffectCapturedInvocation")
pub fn client_program_issue_installed_effect_captured_invocation(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  host : ClientLocalEffectHost,
  compilation : @publication_host.ClientEffectCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  source : @query.CapturedInputSource,
  source_evidence : String,
  input_logical : String,
  source_ref : String,
  source_contract : String,
  authority : String,
  policy : String,
  started : String,
  completed : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @client_local_host.ClientClosedValuesPreparationIssue,
] {
  @client_local_host.issue_installed_effect_captured_invocation(
    owner,
    prepared,
    request,
    plan,
    host.prepared,
    host.run,
    compilation,
    admission,
    definition,
    source,
    source_evidence,
    input_logical,
    source_ref,
    source_contract,
    authority,
    policy,
    started,
    completed,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
#export_name("clientProgramIssueInstalledEffectMultiCapturedInvocation")
pub fn client_program_issue_installed_effect_multi_captured_invocation(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  host : ClientLocalEffectHost,
  compilation : @publication_host.ClientEffectCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  sources : Array[@query.CapturedInputSource],
  identities : Array[@query.CapturedSourceRelationIdentity],
  requirements : Array[@planning.QueryRequirement],
  source_evidence : Array[String],
  input_logical : Array[String],
  authority : String,
  policy : String,
  started : String,
  completed : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @client_local_host.ClientClosedValuesPreparationIssue,
] {
  @client_local_host.issue_installed_effect_multi_captured_invocation(
    owner,
    prepared,
    request,
    plan,
    host.prepared,
    host.run,
    compilation,
    admission,
    definition,
    sources,
    identities,
    requirements,
    source_evidence,
    input_logical,
    authority,
    policy,
    started,
    completed,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
#export_name("clientProgramIssueOriginalEffectDirectSourcesInvocation")
pub fn client_program_issue_original_effect_direct_sources_invocation(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  host : ClientLocalEffectHost,
  compilation : @publication_host.ClientEffectCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  sources : Array[@query.CapturedInputSource],
  identities : Array[@query.CapturedSourceRelationIdentity],
  source_evidence : Array[@publication.RunEvidenceValue],
  input_logical : Array[@publication.RunEvidenceValue],
  authority : String,
  policy : String,
  started : String,
  completed : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectDirectSourcesPublication,
  @client_local_host.ClientClosedValuesPreparationIssue,
] {
  @client_local_host.issue_installed_effect_direct_sources_invocation(
    owner,
    prepared,
    request,
    plan,
    host.prepared,
    host.run,
    compilation,
    admission,
    definition,
    sources,
    identities,
    source_evidence,
    input_logical,
    authority,
    policy,
    started,
    completed,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
#export_name("clientProgramBindInstalledEffectModelInvocation")
pub fn client_program_bind_installed_effect_model_invocation(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  host : ClientLocalEffectHost,
  compilation : @publication_host.ClientEffectCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  compiled : @publication_host.ClientCompiledRun,
  binding : @infer_host.InvocationBinding,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @client_local_host.ClientClosedValuesPreparationIssue,
] {
  @infer_host.bind_installed_effect_publication_invocation(
    owner,
    prepared,
    request,
    plan,
    host.prepared,
    host.run,
    compilation,
    admission,
    definition,
    compiled,
    binding,
  )
}

///|
#export_name("clientProgramIssueInstalledEffectContentInvocation")
pub fn client_program_issue_installed_effect_content_invocation(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  host : ClientLocalEffectHost,
  compilation : @publication_host.ClientEffectCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  compiled : @publication_host.ClientCompiledRun,
  generation : @publication_host.ClientSerializationGeneration,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @client_local_host.ClientClosedValuesPreparationIssue,
] {
  @client_local_host.issue_installed_effect_content_invocation(
    owner,
    prepared,
    request,
    plan,
    host.prepared,
    host.run,
    compilation,
    admission,
    definition,
    compiled,
    generation,
    max_bytes,
    max_nodes,
    max_depth,
  )
}
