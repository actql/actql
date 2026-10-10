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
    @host.prepare_source_free_client_request_identity(
      restored.prepared,
      authority_scope_cid,
      @host.client_request_caller_id(retained_request),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Request(issue))
  }
  match @host.client_request_identity_relation(requested, retained_request) {
    SameRequest => ()
    DifferentRequest => return Err(Start(@host.DifferentRequest))
    ChangedIntent => return Err(Start(@host.ChangedIntent))
  }
  // Retain the codec's exact Owner/compilation/admission/definition together.
  // No fresh invocation, lifetime, start claim or task state is issued here.
  Ok({
    input,
    prepared: restored.prepared,
    request: retained_request,
    compilation: restored.compilation,
    admission: restored.admission,
    definition: restored.run_definition,
    account_id: current.account_id(),
    tuple,
    execution_context_cid,
  })
}
