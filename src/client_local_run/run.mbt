///|
/// References to existing checked, request and publication Owners. This
/// adapter holds no Run state and performs no physical or durable operation.
pub struct LocalRunPlan {
  input : @input.LocalPreparedInput
  prepared : @host.PreparedClientProgram
  request : @host.ClientRequestIdentity
  compilation : @host.ClientTaskCompilation
  compiled : @host.ClientCompiledRun
  admission : @publication.RunPublicationAdmission
  definition : @publication.PublicationContract
  account_id : String
  tuple : @authorization.AccessTuple
  execution_context_cid : String
}

///|
/// Retained result of the existing physical-start Owner for this exact plan.
/// A Source may start before its captured Compute Host can be configured.
pub struct LocalRunPhysicalStart {
  plan : LocalRunPlan
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
  PolicyOriginals(@host.ClientRunPolicyOriginalsIssue)
  OriginalEncoding(@host.ClientJournalEncodingIssue)
  Start(@host.ClientRunStartIssue)
  StartNotPermitted
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
    @host.prepared_client_acquisition_count(prepared) != 0 {
    return false
  }
  relation_profile(prepared)
}

///|
fn relation_profile(prepared : @host.PreparedClientProgram) -> Bool {
  let graph = @host.prepared_client_graph(prepared)
  if @strategy.graph_program_has_effects(graph) ||
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
fn captured_source_profile(prepared : @host.PreparedClientProgram) -> Bool {
  @host.prepared_client_acquisition_count(prepared) == 1 &&
  @strategy.graph_task_count(@host.prepared_client_graph(prepared)) > 1 &&
  relation_profile(prepared)
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
  submitted? : @input.LocalSubmittedPreparation? = None,
) -> Result[LocalRunPlan, LocalRunIssue] {
  prepare_local_run_profile(
    input,
    authority_scope_cid,
    caller_request_id,
    permit,
    current,
    tuple,
    execution_context_cid,
    host_policy_cid,
    run_namespace,
    run_id,
    created_at,
    valid_until,
    source_free_profile,
    None,
    submitted~,
  )
}

///|
/// The installed Host must select the genuine Result policy original before
/// definition issuance. The compilation-only constructor grants no publication.
pub fn prepare_source_free_local_publication_run(
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
  result_policy : (String, String),
  submitted? : @input.LocalSubmittedPreparation? = None,
) -> Result[LocalRunPlan, LocalRunIssue] {
  prepare_local_run_profile(
    input,
    authority_scope_cid,
    caller_request_id,
    permit,
    current,
    tuple,
    execution_context_cid,
    host_policy_cid,
    run_namespace,
    run_id,
    created_at,
    valid_until,
    source_free_profile,
    Some(result_policy),
    submitted~,
  )
}

///|
/// Define the original checked single-Source Run before any acquisition I/O.
/// This issues neither read authority nor evidence that a Source completed.
pub fn prepare_captured_source_local_run(
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
  submitted? : @input.LocalSubmittedPreparation? = None,
) -> Result[LocalRunPlan, LocalRunIssue] {
  prepare_local_run_profile(
    input,
    authority_scope_cid,
    caller_request_id,
    permit,
    current,
    tuple,
    execution_context_cid,
    host_policy_cid,
    run_namespace,
    run_id,
    created_at,
    valid_until,
    captured_source_profile,
    None,
    submitted~,
  )
}

///|
fn prepare_local_run_profile(
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
  profile : (@host.PreparedClientProgram) -> Bool,
  result_policy : (String, String)?,
  submitted? : @input.LocalSubmittedPreparation? = None,
) -> Result[LocalRunPlan, LocalRunIssue] {
  let prepared = @input.local_prepared_program(input)
  if !authorized_input(prepared, permit, current, tuple, execution_context_cid) {
    return Err(AuthorizationMismatch)
  }
  if !profile(prepared) {
    return Err(UnsupportedCapability)
  }
  let request = match
    local_run_request_original(
      input, authority_scope_cid, caller_request_id, submitted,
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
  let compiled = match result_policy {
    None => compiled
    Some((cid, wire)) =>
      match
        @host.with_client_source_free_result_policy(
          compiled,
          cid,
          wire,
          limits.max_evidence_bytes,
          limits.max_evidence_nodes,
          limits.max_evidence_depth,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Admission(issue))
      }
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
    compiled,
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
/// Read-only projection of this same nominal Plan's existing materials and
/// publication policy. The physical Host saves all chunks with first ready
/// acceptance; this value grants no durable custody or permission to start.
pub struct LocalRunTaskMaterialsOriginal {
  plan : LocalRunPlan
  wire : String
  cid : String
  chunks : Array[(String, String)]
  publication_policy_originals : String
}

///|
pub fn capture_local_run_task_materials_original(
  plan : LocalRunPlan,
  environment : @checked.CheckEnvironment,
  environment_wire : String,
  bindings_wire : String?,
) -> Result[LocalRunTaskMaterialsOriginal, LocalRunIssue] {
  let wire = match
    export_local_run_materials(
      plan, environment, environment_wire, bindings_wire,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let cid = match @host.client_task_material_original_cid(wire) {
    Ok(value) => value
    Err(issue) => return Err(OriginalEncoding(issue))
  }
  let chunks = match
    @host.client_task_material_original_chunks(
      @host.client_request_scope_cid(plan.request),
      wire,
    ) {
    Ok(value) => value
    Err(issue) => return Err(OriginalEncoding(issue))
  }
  let publication_policy_originals = match
    @host.issue_client_run_policy_originals(
      plan.prepared,
      compiled=plan.compiled,
    ) {
    Ok(value) => value
    Err(issue) => return Err(PolicyOriginals(issue))
  }
  Ok({ plan, wire, cid, chunks, publication_policy_originals, })
}

///|
pub fn local_run_task_materials_original_cid(
  original : LocalRunTaskMaterialsOriginal,
) -> String {
  original.cid
}

///|
pub fn local_run_task_materials_original_chunks(
  original : LocalRunTaskMaterialsOriginal,
) -> Array[(String, String)] {
  original.chunks.copy()
}

///|
pub fn local_run_task_materials_original_policy(
  original : LocalRunTaskMaterialsOriginal,
) -> String {
  original.publication_policy_originals
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

///|
/// Obtain the original Run's start decision before Source or Compute I/O.
/// This is not a durable journal record or a decision to restart a prior Run.
pub fn confirm_local_run_physical_start(
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
) -> Result[LocalRunPhysicalStart, LocalRunIssue] {
  match
    prepare_local_run_physical_start(
      plan, retained, retained_definition_cid, reserved, physically_unstarted, cancellation_requested,
      pre_start_failure_confirmed, permit, current, tuple, context_cid,
    ) {
    Ok(true) => Ok({ plan, })
    Ok(false) => Err(StartNotPermitted)
    Err(issue) => Err(issue)
  }
}

///|
/// Omission preserves the original source-free request domain. Published
/// Source callers retain their existing exact submitted carrier instead of
/// replacing its input intent with the source-free constant.
fn local_run_request_original(
  input : @input.LocalPreparedInput,
  authority_scope_cid : String,
  request_id : String,
  submitted : @input.LocalSubmittedPreparation?,
) -> Result[@host.ClientRequestIdentity, @host.ClientRequestIdentityIssue] {
  match submitted {
    None =>
      @host.prepare_source_free_client_request_identity(
        @input.local_prepared_program(input),
        authority_scope_cid,
        request_id,
      )
    Some(original) => {
      if !physical_equal(
          input,
          @input.local_submitted_preparation_input(original),
        ) {
        return Err(@host.IdentityMismatch)
      }
      @input.local_submitted_preparation_request(
        original, authority_scope_cid, request_id,
      )
    }
  }
}
