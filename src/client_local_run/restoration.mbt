///|
/// Restore the existing compiled Run and request, rather than issue another
/// definition. The trusted Host selects the original durable row and authored
/// bytes; fresh input provenance alone is neither a journal nor a Run grant.
pub fn restore_source_free_local_run(
  input : @input.LocalPreparedInput,
  materials : String,
  expected_definition_cid : String,
  retained_request : @host.ClientRequestIdentity,
  authority_scope_cid : String,
  permit : @authorization.DispatchAuthorization,
  current : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
  execution_context_cid : String,
  host_policy_cid : String,
) -> Result[LocalRunPlan, LocalRunIssue] {
  let original_input = @input.local_prepared_program(input)
  if !authorized_input(
      original_input, permit, current, tuple, execution_context_cid,
    ) {
    return Err(AuthorizationMismatch)
  }
  if !source_free_profile(original_input) {
    return Err(UnsupportedCapability)
  }
  let restored = match
    restore_local_run_materials(materials, expected_definition_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  restore_source_free_local_run_from_materials(
    input, restored, expected_definition_cid, retained_request, authority_scope_cid,
    permit, current, tuple, execution_context_cid, host_policy_cid,
  )
}

///|
/// Consume an already readmitted codec Owner without decoding or compiling it
/// again. Public fields cannot bypass its exact physical compilation binding.
pub fn restore_source_free_local_run_from_materials(
  input : @input.LocalPreparedInput,
  restored : @host.ClientTaskRunMaterials,
  expected_definition_cid : String,
  retained_request : @host.ClientRequestIdentity,
  authority_scope_cid : String,
  permit : @authorization.DispatchAuthorization,
  current : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
  execution_context_cid : String,
  host_policy_cid : String,
  submitted? : @input.LocalSubmittedPreparation? = None,
) -> Result[LocalRunPlan, LocalRunIssue] {
  restore_local_run_from_materials(
    input,
    restored,
    expected_definition_cid,
    retained_request,
    authority_scope_cid,
    permit,
    current,
    tuple,
    execution_context_cid,
    host_policy_cid,
    source_free_profile,
    submitted~,
  )
}

///|
/// Re-admit the original captured-Source compilation. This grants neither
/// Source read authority nor permission to repeat completed physical work.
pub fn restore_captured_source_local_run_from_materials(
  input : @input.LocalPreparedInput,
  restored : @host.ClientTaskRunMaterials,
  expected_definition_cid : String,
  retained_request : @host.ClientRequestIdentity,
  authority_scope_cid : String,
  permit : @authorization.DispatchAuthorization,
  current : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
  execution_context_cid : String,
  host_policy_cid : String,
  submitted? : @input.LocalSubmittedPreparation? = None,
) -> Result[LocalRunPlan, LocalRunIssue] {
  restore_local_run_from_materials(
    input,
    restored,
    expected_definition_cid,
    retained_request,
    authority_scope_cid,
    permit,
    current,
    tuple,
    execution_context_cid,
    host_policy_cid,
    captured_source_profile,
    submitted~,
  )
}

///|
fn restore_local_run_from_materials(
  input : @input.LocalPreparedInput,
  restored : @host.ClientTaskRunMaterials,
  expected_definition_cid : String,
  retained_request : @host.ClientRequestIdentity,
  authority_scope_cid : String,
  permit : @authorization.DispatchAuthorization,
  current : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
  execution_context_cid : String,
  host_policy_cid : String,
  profile : (@host.PreparedClientProgram) -> Bool,
  submitted? : @input.LocalSubmittedPreparation? = None,
) -> Result[LocalRunPlan, LocalRunIssue] {
  let original_input = @input.local_prepared_program(input)
  if !authorized_input(
      original_input, permit, current, tuple, execution_context_cid,
    ) {
    return Err(AuthorizationMismatch)
  }
  if !profile(original_input) || !profile(restored.prepared) {
    return Err(UnsupportedCapability)
  }
  if @publication.publication_contract_identity(restored.run_definition) !=
    expected_definition_cid {
    return Err(Materials(@host.RunMismatch))
  }
  match
    @host.bind_client_task_run(
      restored.prepared,
      restored.compilation,
      restored.admission,
      restored.run_definition,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Materials(@host.Binding(issue)))
  }
  if @host.prepared_client_identity(original_input) !=
    @host.prepared_client_identity(restored.prepared) ||
    @host.prepared_client_check_environment_cid(original_input) !=
    @host.prepared_client_check_environment_cid(restored.prepared) {
    return Err(Materials(@host.RunMismatch))
  }
  if @publication.run_publication_execution_context(restored.admission) !=
    execution_context_cid ||
    @publication.run_publication_host_policy(restored.admission) !=
    host_policy_cid {
    return Err(AuthorizationMismatch)
  }
  let requested = match
    local_run_request_original(
      input,
      authority_scope_cid,
      @host.client_request_caller_id(retained_request),
      submitted,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Request(issue))
  }
  match @host.client_request_identity_relation(requested, retained_request) {
    SameRequest => ()
    DifferentRequest => return Err(Start(@host.DifferentRequest))
    ChangedIntent => return Err(Start(@host.ChangedIntent))
  }
  let compiled = match
    @host.client_task_run_materials_compiled_original(restored) {
    Ok(value) => value
    Err(issue) => return Err(Admission(issue))
  }
  // Retain the codec's exact Owner/compilation/admission/definition together.
  // No fresh invocation, lifetime, start claim or task state is issued here.
  Ok({
    input,
    prepared: restored.prepared,
    request: retained_request,
    compilation: restored.compilation,
    compiled,
    admission: restored.admission,
    definition: restored.run_definition,
    account_id: current.account_id(),
    tuple,
    execution_context_cid,
  })
}

///|
/// Attach only the policy body retained with this same saved material/Run.
/// The codec's compiled Owner and original definition stay unchanged; no
/// current default, replacement policy, invocation or lifetime is issued.
pub fn restore_source_free_local_run_policy_original(
  plan : LocalRunPlan,
  original : @host.ClientSavedTaskMaterials,
) -> Result[LocalRunPlan, LocalRunIssue] {
  let retained = @host.client_saved_task_materials_input(original)
  let snapshot = @host.client_saved_task_materials_snapshot(original)
  guard physical_equal(
      plan.prepared,
      @host.client_task_run_materials_retained_program(retained),
    ) &&
    @host.client_saved_submission_run_row(snapshot) is Some(row) &&
    @host.decode_client_run_journal_row_with_observation_originals(row.body)
    is Ok((run, Some(_), Some(_))) &&
    run.publication_policy_originals is Some(wire) else {
    return Err(Materials(@host.RunMismatch))
  }
  if @host.client_request_identity_relation(run.request, plan.request) !=
    @host.SameRequest ||
    @publication.publication_contract_identity(run.definition) !=
    @publication.publication_contract_identity(plan.definition) {
    return Err(Materials(@host.RunMismatch))
  }
  let bodies = match @host.read_client_run_policy_originals(wire) {
    Ok(value) => value
    Err(_) => return Err(Admission(@host.InvalidResultPolicy))
  }
  guard bodies.length() > 0 else {
    return Err(Admission(@host.InvalidResultPolicy))
  }
  let compiled = match
    @host.with_client_source_free_result_policy(
      plan.compiled,
      @publication.captured_effect_dependency_body_cid(bodies[0]),
      @publication.captured_effect_dependency_body_json(bodies[0]),
      65536,
      8192,
      64,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Admission(issue))
  }
  match @host.check_client_compiled_run_definition(compiled, plan.definition) {
    Ok(_) => Ok({ ..plan, compiled, })
    Err(issue) => Err(Admission(issue))
  }
}
