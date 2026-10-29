///|
/// Match the installed Effect Host's preparation bounds. These are parsing
/// and static closure limits, not physical capacity or permission grants.
fn client_values_host_effect_limits() -> @host.ClientEffectComputationLimits {
  @host.client_standard_effect_computation_limits()
}

///|
pub(all) enum ClientValuesHostEffectPreparationIssue {
  Input(ClientValuesHostPreparationIssue)
  Program(@host.ClientEffectComputationIssue)
}

///|
/// Retain the exact checked Effect owner. This performs no Source or write I/O.
#export_name("clientValuesHostPrepareEffect")
pub fn client_values_host_prepare_effect(
  document : String,
  format : String,
  environment : @checked.CheckEnvironment,
  parameters : String?,
  publication_environment : @source_publication.PreparedPublishedQueryEnvironment?,
) -> Result[
  @host.PreparedClientEffectComputation,
  ClientValuesHostEffectPreparationIssue,
] {
  let (update_targets, store_targets, command_targets, catalog) = match
    client_values_host_published_effect_parts(
      publication_environment, environment,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Input(Publication(issue)))
  }
  let (selected, supplied) = match
    client_values_host_program_input(format, parameters) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  @host.prepare_client_effect_computation(
    document,
    selected,
    environment,
    supplied,
    [],
    client_values_host_effect_limits(),
    update_targets~,
    store_targets~,
    command_targets~,
    source_catalog=catalog,
  ).map_err(issue => Program(issue))
}

///|
pub(all) enum ClientValuesHostEffectCompilationIssue {
  Manifests(@host.ClientCompilationManifestIssue)
  Compilation(@host.ClientEffectCompilationIssue)
}

///|
fn client_values_host_effect_manifests() -> Result[
  @host.ClientCompilationManifests,
  @host.ClientCompilationManifestIssue,
] {
  @host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  )
}

///|
#export_name("clientValuesHostCompileEffect")
pub fn client_values_host_compile_effect(
  prepared : @host.PreparedClientEffectComputation,
  normalization_profile : Bool,
) -> Result[
  @host.ClientEffectCompilation,
  ClientValuesHostEffectCompilationIssue,
] {
  let manifests = match client_values_host_effect_manifests() {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
  }
  let normalization = if normalization_profile {
    match @host.issue_prepared_client_effect_selected_normalization(prepared) {
      Ok(value) => Some(value)
      Err(issue) => return Err(Compilation(Normalization(issue)))
    }
  } else {
    None
  }
  @host.issue_prepared_client_effect_compilation(
    prepared,
    manifests,
    @host.client_standard_values_sequence_limits(),
    1000,
    10000,
    1000000,
    100000,
    100,
    normalization~,
  ).map_err(issue => Compilation(issue))
}

///|
/// Counts come from the original checked graph, never a Host plan parser.
#export_name("clientValuesHostEffectShape")
pub fn client_values_host_effect_shape(
  compilation : @host.ClientEffectCompilation,
) -> Array[Int] {
  let checked = @host.prepared_client_effect_computation_graph(
    @host.client_effect_compilation_owner(compilation),
  )
  let graph = @strategy.checked_effect_computation_graph(checked)
  [
    @strategy.graph_task_count(graph),
    @strategy.graph_captured_prefix(graph),
    @strategy.checked_effect_source_count(checked),
  ]
}

///|
#export_name("clientValuesHostEffectTemplateWire")
pub fn client_values_host_effect_template_wire(
  compilation : @host.ClientEffectCompilation,
) -> String {
  @publication.run_evidence_value_json(
    @host.client_effect_compilation_template(compilation),
  )
}

///|
#export_name("clientValuesHostEffectCompiledPlanWire")
pub fn client_values_host_effect_compiled_plan_wire(
  compilation : @host.ClientEffectCompilation,
) -> String {
  @publication.publication_contract_json(
    @host.client_effect_compilation_compiled_plan(compilation),
  )
}

///|
/// The Host must authorize the current policy context before issuing a Run.
/// Run admission is distinct from a signed Effect approval or apply permit.
#export_name("clientValuesHostIssueAllowedEffectRun")
pub fn client_values_host_issue_allowed_effect_run(
  compilation : @host.ClientEffectCompilation,
  execution_context_cid : String,
  host_policy_cid : String,
  expires_at : String,
) -> Result[@host.ClientEffectAllowedRun, @host.ClientEffectCompiledRunIssue] {
  @host.issue_client_effect_allowed_run(
    compilation, execution_context_cid, host_policy_cid, expires_at,
  )
}

///|
#export_name("clientValuesHostAllowedEffectPreparedWire")
pub fn client_values_host_allowed_effect_prepared_wire(
  allowed : @host.ClientEffectAllowedRun,
) -> String {
  @publication.run_evidence_value_json(
    @host.client_effect_allowed_run_prepared(allowed),
  )
}

///|
#export_name("clientValuesHostAllowedEffectAuthorizationWire")
pub fn client_values_host_allowed_effect_authorization_wire(
  allowed : @host.ClientEffectAllowedRun,
) -> String {
  @publication.run_evidence_value_json(
    @host.client_effect_allowed_run_authorization(allowed),
  )
}

///|
#export_name("clientValuesHostIssueEffectRunDefinition")
pub fn client_values_host_issue_effect_run_definition(
  allowed : @host.ClientEffectAllowedRun,
  scope_id : String,
  run_id : String,
  created_at : String,
  valid_until : String,
) -> Result[
  @publication.PublicationContract,
  @host.ClientEffectCompiledRunIssue,
] {
  @host.issue_client_effect_run_definition(
    allowed, scope_id, run_id, created_at, valid_until,
  )
}

///|
#export_name("clientValuesHostIssueEffectRunMaterials")
pub fn client_values_host_issue_effect_run_materials(
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  environment : @checked.CheckEnvironment,
  environment_wire : String,
  document : String,
  parameters : String?,
  request : @host.ClientRequestIdentity?,
) -> Result[String, @host.ClientEffectRunMaterialsIssue] {
  @host.issue_client_effect_run_materials(
    allowed,
    definition,
    environment,
    environment_wire,
    document,
    parameters,
    client_values_host_effect_limits(),
    request~,
  )
}

///|
/// Original checked preparation only: the issuer supplies normalization from
/// its actual retained completion inventory, not caller wire or Program shape.
#export_name("clientValuesHostIssuePreparedEffectRunMaterials")
pub fn client_values_host_issue_prepared_effect_run_materials(
  prepared : @host.PreparedClientEffectComputation,
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  request : @host.ClientRequestIdentity?,
) -> Result[
  @host.ClientEffectIssuedNormalizationMaterials,
  @host.ClientEffectRunMaterialsIssue,
] {
  match @host.bind_client_effect_compiled_run(prepared, allowed, definition) {
    Ok(_) => ()
    Err(issue) => return Err(Binding(issue))
  }
  let normalization = match
    @host.issue_prepared_client_effect_selected_normalization(prepared) {
    Ok(value) => value
    Err(issue) => return Err(Normalization(issue))
  }
  @host.issue_prepared_client_effect_normalization_materials(
    allowed,
    definition,
    normalization,
    request~,
  )
}

///|
#export_name("clientValuesHostIssuedEffectRunMaterialsWire")
pub fn client_values_host_issued_effect_run_materials_wire(
  issued : @host.ClientEffectIssuedNormalizationMaterials,
) -> String {
  @host.client_effect_issued_normalization_materials_wire(issued)
}

///|
/// Bind the already-issued live originals without preparing or compiling again.
/// Current Host authority, durable custody and Effect approval stay separate.
#export_name("clientValuesHostBindPreparedEffectRunMaterials")
pub fn client_values_host_bind_prepared_effect_run_materials(
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  issued : @host.ClientEffectIssuedNormalizationMaterials,
  request : @host.ClientRequestIdentity,
) -> Result[@host.ClientEffectRunMaterials, @host.ClientEffectRunMaterialsIssue] {
  @host.bind_prepared_client_effect_original_materials(
    allowed,
    definition,
    issued,
    request=Some(request),
  )
}

///|
/// Restore through the actual admitted material Owner without journal issuance.
#export_name("clientValuesHostRestoreEffectRunNormalization")
pub fn client_values_host_restore_effect_run_normalization(
  materials : @host.ClientEffectRunMaterials,
) -> Result[@publication.RunEvidenceValue, @host.ClientEffectNormalizationIssue] {
  @host.restore_client_effect_run_normalization(materials)
}

///|
pub(all) enum ClientValuesHostEffectRestorationIssue {
  Manifests(@host.ClientCompilationManifestIssue)
  Materials(@host.ClientEffectRunMaterialsIssue)
}

///|
/// Re-admit saved original evidence. Never issue another authorization or Run.
#export_name("clientValuesHostAdmitEffectRunMaterials")
pub fn client_values_host_admit_effect_run_materials(
  wire : String,
  definition_cid : String,
  text_time : Bool,
  veca : Bool,
  rela : Bool,
  sga : Bool,
  tea : Bool,
  calendar : Bool,
  text_rank : Bool,
  original : @host.ClientEffectIssuedNormalizationMaterials?,
  expected_request : @host.ClientRequestIdentity?,
  source_preparation : @local.LocalSourceComputation?,
  numeric_profile_cid : String?,
) -> Result[
  @host.ClientEffectRunMaterials,
  ClientValuesHostEffectRestorationIssue,
] {
  let manifests = match client_values_host_effect_manifests() {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
  }
  @host.admit_client_effect_run_materials(
    wire,
    definition_cid,
    { text_time, veca, },
    { rela, sga, tea, calendar, text_rank, },
    manifests,
    {
      preparation: @host.client_standard_program_preparation_limits(),
      sequence: @host.client_standard_values_sequence_limits(),
      max_sequence_steps: 1000,
      max_sequence_work: 10000,
      max_evidence_bytes: 1000000,
      max_evidence_nodes: 100000,
      max_evidence_depth: 100,
    },
    client_values_host_effect_limits(),
    original_materials=original,
    expected_request~,
    original_source=source_preparation,
    numeric_profile_cid~,
  ).map_err(issue => Materials(issue))
}

///|
#export_name("clientValuesHostRestoredEffectPrepared")
pub fn client_values_host_restored_effect_prepared(
  restored : @host.ClientEffectRunMaterials,
) -> @host.PreparedClientEffectComputation {
  restored.prepared
}

///|
#export_name("clientValuesHostRestoredEffectCompilation")
pub fn client_values_host_restored_effect_compilation(
  restored : @host.ClientEffectRunMaterials,
) -> @host.ClientEffectCompilation {
  restored.compilation
}

///|
#export_name("clientValuesHostRestoredEffectAllowed")
pub fn client_values_host_restored_effect_allowed(
  restored : @host.ClientEffectRunMaterials,
) -> @host.ClientEffectAllowedRun {
  restored.allowed
}

///|
#export_name("clientValuesHostRestoredEffectDefinition")
pub fn client_values_host_restored_effect_definition(
  restored : @host.ClientEffectRunMaterials,
) -> @publication.PublicationContract {
  restored.run_definition
}

///|
#export_name("clientValuesHostRestoredEffectRequest")
pub fn client_values_host_restored_effect_request(
  restored : @host.ClientEffectRunMaterials,
) -> Array[@host.ClientRequestIdentity] {
  // Explicit cardinality avoids depending on optimized optional-struct
  // representations at the generated JavaScript boundary.
  match restored.request {
    None => []
    Some(request) => [request]
  }
}

///|
#export_name("clientValuesHostEffectStartCurrent")
pub fn client_values_host_effect_start_current(
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  at : String,
) -> Bool {
  @host.client_effect_run_start_current(allowed, definition, at)
}
