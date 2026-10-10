///|
/// References to existing checked, request and publication Owners. This
/// adapter holds no Run state and performs no physical or durable operation.
pub struct LocalRunPlan {
  input : @input.LocalPreparedInput
  prepared : @host.PreparedClientProgram
  request : @host.ClientRequestIdentity
  compilation : @host.ClientTaskCompilation
  admission : @publication.RunPublicationAdmission
  definition : @publication.PublicationContract
  account_id : String
  tuple : @authorization.AccessTuple
  execution_context_cid : String
}

///|
pub(all) enum LocalRunIssue {
  AuthorizationMismatch
  UnsupportedCapability
  Request(@host.ClientRequestIdentityIssue)
  Manifests(@host.ClientCompilationManifestIssue)
  Compilation(@host.ClientTaskCompilationIssue)
  Admission(@host.ClientCompiledRunIssue)
  Materials(@host.ClientTaskRunMaterialsIssue)
  Start(@host.ClientRunStartIssue)
}

///|
pub fn local_run_material_limits() -> @host.ClientValuesRunMaterialsLimits {
  {
    preparation: @host.client_standard_program_preparation_limits(),
    sequence: @host.client_standard_values_sequence_limits(),
    max_sequence_steps: 32,
    max_sequence_work: 64,
    max_evidence_bytes: 1000000,
    max_evidence_nodes: 100000,
    max_evidence_depth: 64,
  }
}

///|
fn local_run_manifests() -> Result[
  @host.ClientCompilationManifests,
  LocalRunIssue,
] {
  @host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).map_err(fn(issue) { Manifests(issue) })
}

///|
fn source_free_profile(prepared : @host.PreparedClientProgram) -> Bool {
  let graph = @host.prepared_client_graph(prepared)
  if !@strategy.graph_source_free_inputs_complete(graph) ||
    @strategy.graph_program_has_effects(graph) ||
    @host.prepared_client_acquisition_count(prepared) != 0 ||
    @host.prepared_client_uses_graph_carrier(prepared) {
    return false
  }
  for task in 0..<@strategy.graph_task_count(graph) {
    if @host.prepared_client_infer_execution_occurrence(prepared, task)
      is Some(_) {
      return false
    }
  }
  true
}

///|
fn authorized_input(
  prepared : @host.PreparedClientProgram,
  permit : @authorization.DispatchAuthorization,
  current : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
  context_cid : String,
) -> Bool {
  @authorization.dispatch_authorization_matches(
    permit,
    current,
    tuple,
    @authorization.Activation,
    @host.prepared_client_identity(prepared).program_definition_cid,
    context_cid,
  )
}

///|
/// The Host supplies an evaluated, subject-bound current authorization, not
/// a caller boolean. Issuance alone is never durable acceptance or permission
/// to invoke Compute: the exact request and start facts still pass their Owner.
pub fn prepare_source_free_local_run(
  input : @input.LocalPreparedInput,
  authority_scope_cid : String,
  caller_request_id : String,
  permit : @authorization.DispatchAuthorization,
  current : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
  execution_context_cid : String,
  host_policy_cid : String,
  run_namespace : String,
  run_id : String,
  created_at : String,
  valid_until : String,
) -> Result[LocalRunPlan, LocalRunIssue] {
  let prepared = @input.local_prepared_program(input)
  if !authorized_input(prepared, permit, current, tuple, execution_context_cid) {
    return Err(AuthorizationMismatch)
  }
  if !source_free_profile(prepared) {
    return Err(UnsupportedCapability)
  }
  let request = match
    @host.prepare_source_free_client_request_identity(
      prepared, authority_scope_cid, caller_request_id,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Request(issue))
  }
  let manifests = match local_run_manifests() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let limits = local_run_material_limits()
  let compilation = match
    @host.issue_prepared_client_task_compilation(
      prepared,
      manifests,
      @host.prepared_client_values_sequence_limits(prepared),
      limits.max_sequence_steps,
      limits.max_sequence_work,
      limits.max_evidence_bytes,
      limits.max_evidence_nodes,
      limits.max_evidence_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Compilation(issue))
  }
  let compiled = match
    @host.issue_client_task_compiled_run(
      prepared, compilation, execution_context_cid, host_policy_cid, valid_until,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Admission(issue))
  }
  let definition = match
    @host.issue_client_compiled_run_definition(
      compiled, run_namespace, run_id, created_at, valid_until,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Admission(issue))
  }
  Ok({
    input,
    prepared,
    request,
    compilation,
    admission: @host.client_compiled_run_admission(compiled),
    definition,
    account_id: current.account_id(),
    tuple,
    execution_context_cid,
  })
}

///|
pub fn local_run_request(plan : LocalRunPlan) -> @host.ClientRequestIdentity {
  plan.request
}

///|
/// The compilation-retained execution Owner is distinct from fresh authored
/// input provenance after restoration. Do not replace it with an equivalent
/// freshly checked object: physical binding belongs to the original codec.
pub fn local_run_prepared(plan : LocalRunPlan) -> @host.PreparedClientProgram {
  plan.prepared
}

///|
pub fn local_run_definition(
  plan : LocalRunPlan,
) -> @publication.PublicationContract {
  plan.definition
}

///|
pub fn local_run_definition_cid(plan : LocalRunPlan) -> String {
  @publication.publication_contract_identity(plan.definition)
}

///|
pub fn local_run_compilation(
  plan : LocalRunPlan,
) -> @host.ClientTaskCompilation {
  plan.compilation
}

///|
pub fn local_run_admission(
  plan : LocalRunPlan,
) -> @publication.RunPublicationAdmission {
  plan.admission
}

///|
pub fn export_local_run_materials(
  plan : LocalRunPlan,
  environment : @checked.CheckEnvironment,
  environment_wire : String,
  bindings_wire : String?,
) -> Result[String, LocalRunIssue] {
  @host.issue_client_task_run_materials(
    plan.prepared,
    plan.compilation,
    plan.admission,
    plan.definition,
    environment,
    environment_wire,
    @input.local_prepared_document(plan.input),
    bindings_wire,
  ).map_err(fn(issue) { Materials(issue) })
}

///|
/// Restore the original Run's checked materials, never issue a replacement.
/// This is identity/codec admission only, not permission to restart Compute.
pub fn restore_local_run_materials(
  wire : String,
  expected_definition_cid : String,
) -> Result[@host.ClientTaskRunMaterials, LocalRunIssue] {
  let manifests = match local_run_manifests() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @host.admit_client_task_run_materials(
    wire,
    expected_definition_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    manifests,
    local_run_material_limits(),
  ).map_err(fn(issue) { Materials(issue) })
}

///|
/// The physical journal atomically records the returned decision before IO.
/// A repeated reservation is reconciliation of this same Run, not retry.
pub fn prepare_local_run_start(
  plan : LocalRunPlan,
  retained : @host.ClientRequestIdentity,
  retained_definition_cid : String,
  dispatch_reserved : Bool,
  permit : @authorization.DispatchAuthorization,
  current : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
  context_cid : String,
) -> Result[@host.ClientRunStartAction, LocalRunIssue] {
  @host.prepare_client_run_start(
    plan.request,
    retained,
    plan.definition,
    retained_definition_cid,
    dispatch_reserved,
    current.account_id() == plan.account_id &&
    tuple == plan.tuple &&
    context_cid == plan.execution_context_cid &&
    authorized_input(plan.prepared, permit, current, tuple, context_cid),
  ).map_err(fn(issue) { Start(issue) })
}

///|
pub fn prepare_local_run_physical_start(
  plan : LocalRunPlan,
  retained : @host.ClientRequestIdentity,
  retained_definition_cid : String,
  reserved : Bool,
  physically_unstarted : Bool,
  cancellation_requested : Bool,
  pre_start_failure_confirmed : Bool,
  permit : @authorization.DispatchAuthorization,
  current : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
  context_cid : String,
) -> Result[Bool, LocalRunIssue] {
  @host.prepare_client_run_physical_start(
    plan.request,
    retained,
    plan.definition,
    retained_definition_cid,
    reserved,
    physically_unstarted,
    current.account_id() == plan.account_id &&
    tuple == plan.tuple &&
    context_cid == plan.execution_context_cid &&
    authorized_input(plan.prepared, permit, current, tuple, context_cid),
    cancellation_requested~,
    pre_start_failure_confirmed~,
  ).map_err(fn(issue) { Start(issue) })
}
