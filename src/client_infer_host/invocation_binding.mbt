///|
/// Exact completed execution-to-Run binding for the initial INFER route.
/// Structural observation verification is retained separately from admission
/// of attempts, accounting, egress and private Store custody. A publisher must
/// still obtain those authorities before it can commit a Named Result.
struct ExecutionRunBinding {
  compiled : @publication_host.ClientCompiledRun
  definition : @publication.PublicationContract
}

///|
pub struct InvocationBinding {
  output_use : OutputUse
  observation : @publication.RunEvidenceValue
  invocation : @publication.PublicationContract
  issuance : ObservationIssuance?
}

///|
pub(all) enum InvocationBindingIssue {
  ForeignRun
  IncompleteExecution
  UnverifiedSlots
  Evidence(@publication.RunEvidenceValueIssue)
} derive(Eq, Debug)

///|
/// The installed Run owner binds its checked admission before the first
/// advance. Completed work cannot be retroactively adopted by another Run.
/// This grants neither model egress nor publication permission.
pub fn bind_run(
  active : Execution,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[Unit, InvocationBindingIssue] {
  if !@publication_host.client_compiled_run_matches(compiled, active.prepared) ||
    @publication_host.check_client_compiled_run_definition(compiled, definition)
    is Err(_) {
    return Err(ForeignRun)
  }
  guard active.plan is Some(plan) &&
    @publication_host.client_compiled_run_infer(compiled) is Some(selected) &&
    physical_equal(plan, selected) else {
    return Err(ForeignRun)
  }
  if active.reclaimed || active.cancelled || active.advancing {
    return Err(IncompleteExecution)
  }
  if active.run_binding is Some(bound) {
    if physical_equal(bound.compiled, compiled) &&
      @publication.publication_contract_identity(bound.definition) ==
      @publication.publication_contract_identity(definition) {
      return Ok(())
    }
    return Err(ForeignRun)
  }
  if !(active.phase is Input) || active.work != 0L {
    return Err(IncompleteExecution)
  }
  active.run_binding = Some({ compiled, definition, })
  Ok(())
}

///|
/// Bind existing dispatch authority before any progress; evidence cannot
/// retrospectively legitimize a physical call. Replay never needs this.
pub fn bind_dispatch_admission(
  active : Execution,
  admission : @publication_host.ClientInferDispatchAdmission,
) -> Result[Unit, InvocationBindingIssue] {
  guard active.run_binding is Some(bound) &&
    @publication_host.client_infer_dispatch_matches_run(
      admission,
      bound.compiled,
      bound.definition,
    ) else {
    return Err(ForeignRun)
  }
  if active.reclaimed ||
    active.cancelled ||
    active.advancing ||
    !(active.phase is Input) ||
    active.work != 0L ||
    !(active.source is Physical(_)) ||
    active.dispatch_admission is Some(_) {
    return Err(IncompleteExecution)
  }
  active.dispatch_admission = Some(admission)
  Ok(())
}

///|
pub fn stopped_attempt_count(active : Execution) -> Int? {
  if active.reclaimed || !(active.phase is Terminal) {
    return None
  }
  match active.model {
    Some(model) => @model.stopped_model_attempt_count(model)
    None => Some(0)
  }
}

///|
pub fn attempt_evidence(
  active : Execution,
  slot : Int,
) -> Result[@model.ModelAttemptEvidence, @model.ModelExecutionIssue] {
  guard active.model is Some(model) else { return Err(@model.OutputIdentity) }
  @model.model_execution_attempt_evidence(model, slot)
}

///|
pub fn issued_slot_capture(
  active : Execution,
  slot : Int,
) -> Result[@publication.RunEvidenceValue, @model.ModelExecutionIssue] {
  guard active.model is Some(model) else { return Err(@model.OutputIdentity) }
  @model.model_execution_issued_slot_capture(model, slot)
}

///|
/// Bind without preparing another Program, compiling again or traversing all
/// slots synchronously. The bounded verifier must have checked this execution.
/// Acquire output custody only after every binding check succeeds.
pub fn bind_invocation(
  active : Execution,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  verified : @model.ModelObservationVerification,
  invocation : @publication.PublicationContract,
  data_policy_cid : String,
) -> Result[InvocationBinding, InvocationBindingIssue] {
  guard active.run_binding is Some(bound) &&
    physical_equal(bound.compiled, compiled) &&
    @publication.publication_contract_identity(bound.definition) ==
    @publication.publication_contract_identity(definition) else {
    return Err(ForeignRun)
  }
  if !@publication_host.client_compiled_run_matches(compiled, active.prepared) ||
    @publication_host.check_client_compiled_run_definition(compiled, definition)
    is Err(_) {
    return Err(ForeignRun)
  }
  guard active.plan is Some(plan) &&
    @publication_host.client_compiled_run_infer(compiled) is Some(selected) &&
    physical_equal(plan, selected) else {
    return Err(ForeignRun)
  }
  guard !active.reclaimed &&
    !active.cancelled &&
    active.phase is Terminal &&
    active.completed is Some(_) &&
    active.call_scope is Some(scope) &&
    active.model is Some(model) else {
    return Err(IncompleteExecution)
  }
  guard @model.model_observation_verification_matches(verified, model) &&
    @model.model_observation_verification_value(verified) is Some(observation) else {
    return Err(UnverifiedSlots)
  }
  match
    @publication.check_model_invocation_binding(
      @publication_host.client_compiled_run_template(compiled),
      observation,
      invocation,
      @publication_host.client_infer_call_scope_artifact(scope),
      data_policy_cid,
      source=active.acquired_input.map(
        @publication_host.client_infer_captured_input_observation,
      ),
    ) {
    Err(issue) => return Err(Evidence(issue))
    Ok(_) => ()
  }
  guard acquire_output(active) is Some(output_use) else {
    return Err(IncompleteExecution)
  }
  Ok({ output_use, observation, invocation, issuance: None, })
}

///|
/// Independent publication custody does not revoke another output consumer.
pub fn invocation_binding_output(
  binding : InvocationBinding,
) -> @relation.CompletedOutput? {
  output(binding.output_use)
}

///|
pub fn invocation_binding_observation(
  binding : InvocationBinding,
) -> @publication.RunEvidenceValue? {
  if binding.output_use.released || binding.output_use.owner.reclaimed {
    None
  } else {
    Some(binding.observation)
  }
}

///|
pub fn invocation_binding_invocation(
  binding : InvocationBinding,
) -> @publication.PublicationContract? {
  if binding.output_use.released || binding.output_use.owner.reclaimed {
    None
  } else {
    Some(binding.invocation)
  }
}

///|
pub fn release_invocation_binding(binding : InvocationBinding) -> Bool {
  if !release_output(binding.output_use) {
    return false
  }
  if binding.issuance is Some(issued) {
    issued.uses -= 1
  }
  true
}
