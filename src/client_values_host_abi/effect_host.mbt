///|
/// Match the installed Effect Host's preparation bounds. These are parsing
/// and static closure limits, not physical capacity or permission grants.
fn client_values_host_effect_limits() -> @host.ClientEffectComputationLimits {
  {
    program: @host.client_standard_program_preparation_limits(),
    max_members: 1024,
    max_header_work: 1000000,
    mapping: {
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 64,
      max_members: 256,
    },
    max_mapping_work: 100000,
    effects: {
      max_members: 1024,
      max_work: 1000000,
      max_admission_nodes: 100000,
      max_admission_depth: 64,
      max_admission_text_bytes: 1000000,
    },
  }
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
) -> Result[
  @host.PreparedClientEffectComputation,
  ClientValuesHostEffectPreparationIssue,
] {
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
) -> Result[
  @host.ClientEffectCompilation,
  ClientValuesHostEffectCompilationIssue,
] {
  let manifests = match client_values_host_effect_manifests() {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
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
) -> @host.ClientRequestIdentity? {
  restored.request
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
