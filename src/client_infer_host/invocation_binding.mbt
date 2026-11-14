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
  if !@publication_host.client_infer_occurrence_matches_compiled_run(
      active.occurrence,
      compiled,
    ) ||
    @publication_host.check_client_compiled_run_definition(compiled, definition)
    is Err(_) {
    return Err(ForeignRun)
  }
  guard active.plan is Some(plan) &&
    @publication_host.client_compiled_run_has_infer(compiled, plan) else {
    return Err(ForeignRun)
  }
  if active.serialized_generation is Some(generation) &&
    @publication_host.client_serialization_generation_capture_for(
      generation, compiled, definition,
    )
    is None {
    return Err(ForeignRun)
  }
  if active.saved_call_scope is Some(saved) &&
    !@publication_host.client_infer_saved_call_scope_matches_run(
      saved, compiled, definition,
    ) {
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
  if !(active.phase is Input) || !execution_input_unadvanced(active) {
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
    !execution_input_unadvanced(active) ||
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
/// Same original stopped Model cleanup observation, before immutable proof.
/// Reader retirement is neither a successful Run nor physical cleanup ACK.
pub fn advance_stopped_attempt_raw_usage(
  active : Execution,
  slot : Int,
  quantum : Int,
) -> Result[
  (Bool, Int64, @model.ModelExecutionIssue?),
  @model.ModelExecutionIssue,
] {
  guard !active.reclaimed &&
    !active.advancing &&
    active.phase is Terminal &&
    active.model is Some(model) else {
    return Err(@model.OutputIdentity)
  }
  active.advancing = true
  let result = @model.advance_model_stopped_raw_usage(model, slot, quantum)
  active.advancing = false
  result
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
pub fn issued_attachment_admission(
  active : Execution,
  slot : Int,
) -> Result[@publication.RunEvidenceValue?, @model.ModelExecutionIssue] {
  guard active.model is Some(model) else { return Err(@model.OutputIdentity) }
  @model.model_execution_issued_attachment_admission(model, slot)
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
  if !@publication_host.client_infer_occurrence_matches_compiled_run(
      active.occurrence,
      compiled,
    ) ||
    @publication_host.check_client_compiled_run_definition(compiled, definition)
    is Err(_) {
    return Err(ForeignRun)
  }
  guard active.plan is Some(plan) &&
    @publication_host.client_compiled_run_has_infer(compiled, plan) else {
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
      sources=@publication_host.client_infer_call_scope_source_observations(
        scope,
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
  if !invocation_binding_available(binding) {
    return None
  }
  output(binding.output_use)
}

///|
fn invocation_binding_available(binding : InvocationBinding) -> Bool {
  !binding.output_use.released &&
  !binding.output_use.owner.reclaimed &&
  binding.issuance
  .map(issued => observation_issuance_value(issued) is Some(_))
  .unwrap_or(true)
}

///|
pub fn invocation_binding_observation(
  binding : InvocationBinding,
) -> @publication.RunEvidenceValue? {
  if !invocation_binding_available(binding) {
    None
  } else {
    Some(binding.observation)
  }
}

///|
pub fn invocation_binding_invocation(
  binding : InvocationBinding,
) -> @publication.PublicationContract? {
  if !invocation_binding_available(binding) {
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

///|
/// Original opaque execution binding, while its output/issuance remains live.
/// Definition is immutable admitted canonical DATA: a Journal read can admit
/// the SAME Run bytes into a different allocation. That DATA cannot replace
/// this execution's actual output use, original compiled owner or live issuance.
/// No parser/hash/issuer runs here; the closed Effect transition separately
/// requires its exact Request/Plan/captured DAG/admission/current originals.
pub fn invocation_binding_matches_run(
  binding : InvocationBinding,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Bool {
  guard !binding.output_use.released &&
    !binding.output_use.owner.reclaimed &&
    binding.output_use.owner.run_binding is Some(original) &&
    physical_equal(original.compiled, compiled) else {
    return false
  }
  if !physical_equal(original.definition, definition) &&
    (
      @publication.publication_contract_name(original.definition) !=
      "run_definition" ||
      @publication.publication_contract_name(definition) != "run_definition" ||
      @publication.publication_contract_identity(original.definition) !=
      @publication.publication_contract_identity(definition) ||
      @publication.publication_contract_json(original.definition) !=
      @publication.publication_contract_json(definition)
    ) {
    return false
  }
  invocation_binding_available(binding) &&
  invocation_binding_has_original_run(binding, original)
}

///|
// Cheap post-callback fence over the SAME immutable execution binding. This
// never caches availability or repeats admitted Definition wire comparison.
fn invocation_binding_has_original_run(
  binding : InvocationBinding,
  original : ExecutionRunBinding,
) -> Bool {
  !binding.output_use.released &&
  !binding.output_use.owner.reclaimed &&
  binding.output_use.owner.run_binding is Some(current) &&
  physical_equal(current, original)
}

///|
/// CLOSED Model handoff to the actual managed Effect publication transition.
/// This module owns InvocationBinding and reads its exact borrowed fields
/// without allocating projection Options before the original numeric grow.
/// The receipt stays synchronous and is always consumed/aborted in this call.
pub fn bind_installed_effect_publication_invocation(
  owner : @input.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @input.ClientInstalledEffectManagedPlan,
  bound : @publication_host.PreparedClientEffectRun,
  captured : @strategy.CapturedEffectRunDAG,
  compilation : @publication_host.ClientEffectCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  compiled : @publication_host.ClientCompiledRun,
  binding : InvocationBinding,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @input.ClientClosedValuesPreparationIssue,
] {
  guard binding.output_use.owner.run_binding is Some(original_run) else {
    return Err(@input.ForeignOriginal)
  }
  if !@publication_host.client_compiled_run_matches_effect(
      compiled, prepared, compilation,
    ) ||
    !invocation_binding_matches_run(binding, compiled, definition) ||
    !invocation_binding_has_original_run(binding, original_run) {
    return Err(@input.ForeignOriginal)
  }
  let transition = match
    @input.begin_installed_effect_model_publication_transition(
      owner,
      prepared,
      request,
      plan,
      bound,
      captured,
      compilation,
      admission,
      definition,
      binding.observation,
      binding.invocation,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  defer @input.abort_installed_effect_model_publication_transition(transition)
  // Begin's real current callback can retire the output. Read this SAME
  // existing binding after it, before any model cleanup/publication retirement.
  // Definition DATA was compared once before Begin. Its original immutable
  // binding remains exact; after actual callbacks, reobserve live issuance
  // and that same original record without another wire walk/admission.
  if !invocation_binding_available(binding) ||
    !invocation_binding_has_original_run(binding, original_run) {
    return Err(@input.ForeignOriginal)
  }
  @input.finish_installed_effect_model_publication_transition(
    transition,
    binding.observation,
    binding.invocation,
  )
}
