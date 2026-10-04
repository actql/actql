///|
/// The installed Host selects the common checked occurrence, not an AST index.
#export_name("clientProgramTerminalInferStep")
pub fn client_program_terminal_infer_step(
  prepared : @publication_host.PreparedClientProgram,
) -> Int? {
  @publication_host.prepared_client_terminal_infer_step(prepared)
}

///|
#export_name("clientProgramSelectedInferStep")
pub fn client_program_selected_infer_step(
  prepared : @publication_host.PreparedClientProgram,
) -> Int? {
  @publication_host.prepared_client_infer_step(prepared)
}

///|
#export_name("clientProgramPrepareInferComputeSuffix")
pub fn client_program_prepare_infer_compute_suffix(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  registry : String,
  values : String,
  fragment : String,
  ordered : String,
) -> Result[@execution.GeneratedSequence?, @infer_host.Issue] {
  if @publication_host.prepared_client_terminal_infer_step(prepared) ==
    Some(step) {
    return Ok(None)
  }
  guard @publication_host.prepared_client_infer_step(prepared) == Some(step) &&
    @client_local_host.prepare_client_infer_suffix(
      prepared,
      step,
      registry,
      values,
      fragment_body=Some(fragment),
      ordered_body=Some(ordered),
    )
    is Some(sequence) else {
    return Err(@infer_host.InvalidAdvance)
  }
  let limits = @infer_host.standard_limits()
  guard @local.local_bounded_relation_provider(
      limits.input,
      limits.measurement,
      sequence,
    )
    is Some(_) else {
    return Err(@infer_host.InvalidAdvance)
  }
  Ok(Some(sequence))
}

///|
#export_name("clientProgramBindInferComputeSuffix")
pub fn client_program_bind_infer_compute_suffix(
  active : @infer_host.Execution,
  sequence : @execution.GeneratedSequence,
) -> Result[Unit, @infer_host.Issue] {
  @infer_host.bind_compute_suffix(active, sequence)
}

///|
#export_name("clientProgramInferModelTaskCid")
pub fn client_program_infer_model_task_cid(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
) -> String? {
  @publication_host.prepared_client_infer_model_task_cid(prepared, step)
}

///|
/// Physical capacity cannot grant dispatch permission. The common execution
/// Contract clamps each installed ceiling before any bounded prefix work.
#export_name("clientProgramBindInferQuantityCapacity")
pub fn client_program_bind_infer_quantity_capacity(
  active : @infer_host.Execution,
  tokens : Int64,
  cost_units : Int64,
  duration_ms : Int64,
  per_attempt_tokens : Int64,
  per_attempt_cost_units : Int64,
  per_attempt_duration_ms : Int64,
) -> Result[Unit, @infer_host.Issue] {
  @infer_host.bind_quantity_capacity(active, {
    limits: { tokens, cost_units, duration_ms, },
    per_attempt: {
      tokens: per_attempt_tokens,
      cost_units: per_attempt_cost_units,
      duration_ms: per_attempt_duration_ms,
    },
  })
}

///|
#export_name("clientProgramBindInferPhysicalPreflight")
pub fn client_program_bind_infer_physical_preflight(
  active : @infer_host.Execution,
  prepare : (@model.ModelRequest) -> @model.ModelRequestPreflight?,
) -> Result[Unit, @infer_host.Issue] {
  @infer_host.bind_physical_preflight(active, request => {
    match prepare(request) {
      Some(cursor) => Ok(cursor)
      None => Err(@model.InvalidProvider)
    }
  })
}

///|
/// One bounded physical preparation unit per advance. Invalid terminal
/// preparation is a barrier refusal, never a fabricated provider outcome.
#export_name("clientProgramModelRequestPreflight")
pub fn client_program_model_request_preflight(
  advance : () -> (Bool, @model.ModelPhysicalRequestPlan?),
  cleanup : () -> Bool,
) -> @model.ModelRequestPreflight {
  {
    advance: () => {
      match advance() {
        (false, None) => Ok(None)
        (true, Some(plan)) => Ok(Some(plan))
        _ => Err(@model.InvalidProvider)
      }
    },
    cleanup,
  }
}

///|
/// The payload stays in the installed adapter's closure. MoonBit checks its
/// exact request owner and its envelope against all pre-reserved slot limits.
#export_name("clientProgramModelPhysicalRequestPlan")
pub fn client_program_model_physical_request_plan(
  request : @model.ModelRequest,
  wire_bytes : Int64,
  tokens : Int64,
  cost_units : Int64,
  duration_ms : Int64,
  invoke : () -> @model.ModelResponse?,
) -> Result[@model.ModelPhysicalRequestPlan, @model.ModelExecutionIssue] {
  @model.model_physical_request_plan(
    request,
    wire_bytes,
    { tokens, cost_units, duration_ms, },
    () => {
      match invoke() {
        Some(response) => Ok(response)
        None => Err(@model.ProviderError)
      }
    },
  )
}

///|
#export_name("clientProgramInferQuantityUsage")
pub fn client_program_infer_quantity_usage(
  active : @infer_host.Execution,
) -> @resources.QuantityUsage? {
  @infer_host.execution_quantity_usage(active)
}

///|
/// Compile the retained checked barrier through the existing task Run owner.
/// Compilation does not grant model egress or attest to captured execution.
#export_name("clientProgramCompileLocalInfer")
pub fn client_program_compile_local_infer(
  prepared : @publication_host.PreparedClientProgram,
  graph : @publication_host.ClientInferPlanGraph,
) -> Result[
  @publication_host.ClientTaskCompilation,
  ClientProgramTaskCompilationBridgeIssue,
] {
  let manifests = match
    @publication_host.admit_client_compilation_manifests(
      @check_environment.compiler_grammar_manifest_wire(),
      @check_environment.compiler_barrier_contract_manifest_wire(),
      100000,
      10000,
      100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
  }
  @publication_host.issue_prepared_client_infer_compilation(
    prepared, graph, manifests, 1000, 10000, 1000000, 100000, 100,
  ).map_err(issue => Compilation(issue))
}

///|
/// The installed Host retains the checked barrier and derives call identity
/// from the exact completed input before the first physical model dispatch.

///|
#export_name("clientProgramAdmitInferCapturedInput")
pub fn client_program_admit_infer_captured_input(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  source : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  logical : @publication.RunEvidenceValue,
  source_evidence_wire : String,
  authority_scope_cid : String,
  data_policy_cid : String,
  started_at : String,
  completed_at : String,
) -> Result[
  @publication_host.ClientInferCapturedInput,
  @publication_host.ClientInferCallScopeIssue,
] {
  let source_evidence = match
    @publication.admit_run_evidence_value(
      "source_evidence", source_evidence_wire, 100000, 10000, 100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(@publication_host.Evidence(issue))
  }
  let (source_ref, source_contract) = @planning.query_requirement_source(
    requirement,
  )
  let observation = match
    @publication.admit_model_source_observation(
      source_evidence, logical, source_ref, source_contract, authority_scope_cid,
      data_policy_cid, started_at, completed_at,
    ) {
    Ok(value) => value
    Err(issue) => return Err(@publication_host.Evidence(issue))
  }
  @publication_host.admit_client_infer_captured_input(
    prepared, step, source, identity, requirement, logical, observation,
  )
}

///|
#export_name("clientProgramStartAcquiredInferExecution")
pub fn client_program_start_acquired_infer_execution(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  graph : @publication_host.ClientInferPlanGraph,
  registry : String,
  values : String,
  provider : @model.ModelProvider,
  input : @publication_host.ClientInferCapturedInput,
  fragment : String,
  ordered : String,
) -> Result[@infer_host.Execution, @infer_host.Issue] {
  @infer_host.start(
    prepared,
    step,
    registry,
    values,
    provider,
    @publication_host.client_infer_plan_graph_request_cid(graph),
    @infer_host.standard_limits(),
    plan=Some(graph),
    acquired_input=Some(input),
    fragment_body=Some(fragment),
    ordered_body=Some(ordered),
  )
}

///|
#export_name("clientProgramRestoreInferCapturedInput")
pub fn client_program_restore_infer_captured_input(
  input : @publication_host.ClientInferCapturedInput,
  source : @publication.RunEvidenceValue,
  observation : @publication.RunEvidenceValue,
) -> Result[
  @publication_host.ClientInferCapturedInput,
  @publication_host.ClientInferCallScopeIssue,
] {
  @publication_host.restore_client_infer_captured_input(
    input, source, observation,
  )
}

///|
#export_name("clientProgramStartAcquiredInferSlotReplay")
pub fn client_program_start_acquired_infer_slot_replay(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  graph : @publication_host.ClientInferPlanGraph,
  registry : String,
  values : String,
  read : @model.ModelSlotReplayRead,
  input : @publication_host.ClientInferCapturedInput,
  fragment : String,
  ordered : String,
) -> Result[@infer_host.Execution, @infer_host.Issue] {
  @infer_host.start_restored_slot_replay(
    prepared,
    step,
    registry,
    values,
    read,
    @infer_host.standard_limits(),
    graph,
    acquired_input=Some(input),
    fragment_body=Some(fragment),
    ordered_body=Some(ordered),
  )
}

///|
#export_name("clientProgramStartScopedInferExecution")
pub fn client_program_start_scoped_infer_execution(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  graph : @publication_host.ClientInferPlanGraph,
  registry : String,
  values : String,
  provider : @model.ModelProvider,
  fragment : String,
  ordered : String,
) -> Result[@infer_host.Execution, @infer_host.Issue] {
  @infer_host.start(
    prepared,
    step,
    registry,
    values,
    provider,
    @publication_host.client_infer_plan_graph_request_cid(graph),
    @infer_host.standard_limits(),
    plan=Some(graph),
    fragment_body=Some(fragment),
    ordered_body=Some(ordered),
  )
}

///|
/// Run the original Program prefix and physical preflight, then retain the
/// complete call inventory without entering a provider. The callback must
/// durably record each owner-issued attempt before returning true.
#export_name("clientProgramStartScopedEnteredInferExecution")
pub fn client_program_start_scoped_entered_infer_execution(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  graph : @publication_host.ClientInferPlanGraph,
  registry : String,
  values : String,
  provider : @model.ModelProvider,
  fragment : String,
  ordered : String,
  enter_call : (@model.ModelCallEntry) -> Bool,
  deferred : Bool,
) -> Result[@infer_host.Execution, @infer_host.Issue] {
  @infer_host.start(
    prepared,
    step,
    registry,
    values,
    provider,
    @publication_host.client_infer_plan_graph_request_cid(graph),
    @infer_host.standard_limits(),
    plan=Some(graph),
    fragment_body=Some(fragment),
    ordered_body=Some(ordered),
    defer_dispatch=deferred,
    enter_call=Some(enter_call),
  )
}

///|
#export_name("clientProgramStartAcquiredEnteredInferExecution")
pub fn client_program_start_acquired_entered_infer_execution(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  graph : @publication_host.ClientInferPlanGraph,
  registry : String,
  values : String,
  provider : @model.ModelProvider,
  input : @publication_host.ClientInferCapturedInput,
  fragment : String,
  ordered : String,
  enter_call : (@model.ModelCallEntry) -> Bool,
  deferred : Bool,
) -> Result[@infer_host.Execution, @infer_host.Issue] {
  @infer_host.start(
    prepared,
    step,
    registry,
    values,
    provider,
    @publication_host.client_infer_plan_graph_request_cid(graph),
    @infer_host.standard_limits(),
    plan=Some(graph),
    acquired_input=Some(input),
    fragment_body=Some(fragment),
    ordered_body=Some(ordered),
    defer_dispatch=deferred,
    enter_call=Some(enter_call),
  )
}

///|
#export_name("clientProgramInferPreparedCallSet")
pub fn client_program_infer_prepared_call_set(
  active : @infer_host.Execution,
) -> @model.PreparedModelCallSet? {
  @infer_host.prepared_model_call_set(active)
}

///|
#export_name("clientProgramInferPreparedCallCount")
pub fn client_program_infer_prepared_call_count(
  set : @model.PreparedModelCallSet,
) -> Int? {
  @model.prepared_model_call_set_count(set)
}

///|
#export_name("clientProgramInferPreparedInputWire")
pub fn client_program_infer_prepared_input_wire(
  set : @model.PreparedModelCallSet,
) -> String? {
  @model.prepared_model_call_set_input(set).map(
    @publication.run_evidence_value_json,
  )
}

///|
#export_name("clientProgramInferPreparedSlotWire")
pub fn client_program_infer_prepared_slot_wire(
  set : @model.PreparedModelCallSet,
  index : Int,
) -> String? {
  @model.prepared_model_call_set_slot(set, index).map(
    @publication.run_evidence_value_json,
  )
}

///|
/// The Checkpoint grant, current dispatch admission, and still-retained
/// prepared inventory must all belong to the same original Run and call set.
#export_name("clientProgramResumeApprovedInferExecution")
pub fn client_program_resume_approved_infer_execution(
  active : @infer_host.Execution,
  grant : @checkpoint.ModelInvocationGrant,
  admission : @publication_host.ClientInferDispatchAdmission,
  now : () -> String,
  current : () -> Bool,
) -> Result[Unit, @infer_host.Issue] {
  @infer_host.resume_approved_model_call_set(
    active, grant, admission, now, current,
  )
}

///|
/// Ordinary allow continues after input completion without a synthetic
/// reviewer approval or Checkpoint.
#export_name("clientProgramResumeImmediateInferExecution")
pub fn client_program_resume_immediate_infer_execution(
  active : @infer_host.Execution,
  admission : @publication_host.ClientInferDispatchAdmission,
  current : () -> Bool,
) -> Result[Unit, @infer_host.Issue] {
  @infer_host.resume_immediate_model_call_set(active, admission, current)
}

///|
/// The retained journal readback is re-admitted in this runtime so the
/// execution owner receives a typed grant, not an adapter-created summary.
#export_name("clientProgramModelInvocationGrantHandle")
pub fn client_program_model_invocation_grant_handle(
  request_wire : String,
  checkpoint_wire : String,
  verified_wire : String,
  at : String,
  immediate : Bool,
) -> Result[@checkpoint.ModelInvocationGrant, String] {
  @checkpoint_node.model_invocation_grant_handle(
    request_wire, checkpoint_wire, verified_wire, at, immediate,
  )
}

///|
#export_name("clientProgramInferCallEntryOriginals")
pub fn client_program_infer_call_entry_originals(
  value : @model.ModelCallEntry,
) -> (Int, String, String, String) {
  (
    @model.model_call_entry_slot(value),
    @publication.run_evidence_value_json(@model.model_call_entry_call(value)),
    @publication.run_evidence_value_json(@model.model_call_entry_attempt(value)),
    @publication.run_evidence_value_json(
      @model.model_call_entry_authority(value),
    ),
  )
}

///|
/// Replay has no physical provider and prepares the normal input again.
#export_name("clientProgramStartInferReplay")
pub fn client_program_start_infer_replay(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  graph : @publication_host.ClientInferPlanGraph,
  registry : String,
  values : String,
  capture : @model.VerifiedModelCapture,
  fragment : String,
  ordered : String,
) -> Result[@infer_host.Execution, @infer_host.Issue] {
  @infer_host.start_replay(
    prepared,
    step,
    registry,
    values,
    capture,
    @infer_host.standard_limits(),
    graph,
    fragment_body=Some(fragment),
    ordered_body=Some(ordered),
  )
}

///|
#export_name("clientProgramAcquireInferCapture")
pub fn client_program_acquire_infer_capture(
  active : @infer_host.Execution,
) -> @model.VerifiedModelCapture? {
  @infer_host.acquire_capture(active)
}

///|
/// The installing publication owner supplies this physical metadata envelope.
/// It is distinct from model attempts, usage observations and logical budgets;
/// creating capacity grants neither dispatch nor publication authority.
#export_name("clientProgramInferPublicationLedger")
pub fn client_program_infer_publication_ledger(
  retained_bytes : Int64,
  planning_work : Int,
) -> Result[@resources.Ledger, @resources.LedgerIssue] {
  @resources.create_ledger({
    retained_bytes,
    planning_work,
    attempts: 1,
    holdings: 0,
    transfer_bytes: 0L,
    execution_bytes: 0L,
  })
}

///|
#export_name("clientProgramInferPublicationUsage")
pub fn client_program_infer_publication_usage(
  ledger : @resources.Ledger,
) -> (Int, Int64) {
  let usage = @resources.ledger_usage(ledger)
  (usage.planning_work, usage.reserved_retention_bytes)
}

///|
#export_name("clientProgramStartInferObservationIssuance")
pub fn client_program_start_infer_observation_issuance(
  active : @infer_host.Execution,
  ledger : @resources.Ledger,
  max_slots : Int,
  max_wire_bytes : Int,
  max_work : Int,
) -> Result[@infer_host.ObservationIssuance, @infer_host.Issue] {
  @infer_host.start_observation_issuance(active, ledger, {
    max_slots,
    max_wire_bytes,
    max_work,
  })
}

///|
#export_name("clientProgramAdvanceInferObservationIssuance")
pub fn client_program_advance_infer_observation_issuance(
  active : @infer_host.ObservationIssuance,
  quantum : Int,
) -> Result[(Bool, Int64), @infer_host.Issue] {
  @infer_host.advance_observation_issuance(active, quantum)
}

///|
#export_name("clientProgramCancelInferObservationIssuance")
pub fn client_program_cancel_infer_observation_issuance(
  active : @infer_host.ObservationIssuance,
) -> Bool {
  @infer_host.cancel_observation_issuance(active)
}

///|
#export_name("clientProgramCleanupInferObservationIssuance")
pub fn client_program_cleanup_infer_observation_issuance(
  active : @infer_host.ObservationIssuance,
) -> Result[Bool, @infer_host.Issue] {
  @infer_host.cleanup_observation_issuance(active)
}

///|
#export_name("clientProgramBindIssuedInferInvocation")
pub fn client_program_bind_issued_infer_invocation(
  execution : @infer_host.Execution,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  issued : @infer_host.ObservationIssuance,
) -> Result[@infer_host.InvocationBinding, @infer_host.InvocationBindingIssue] {
  @infer_host.bind_issued_invocation(execution, compiled, definition, issued)
}

///|
/// Existing bounded all-slot verification. External evidence and Store
/// confirmation remain the installing capture owner's responsibilities.
#export_name("clientProgramStartInferObservationVerification")
pub fn client_program_start_infer_observation_verification(
  capture : @model.VerifiedModelCapture,
  observation : @publication.RunEvidenceValue,
  records : Array[@publication.RunEvidenceValue],
  max_slots : Int,
  max_slot_wire_units : Int,
  max_work : Int,
) -> Result[@model.ModelObservationVerification, @model.ModelExecutionIssue] {
  @model.start_model_observation_verification(capture, observation, records, {
    max_slots,
    max_slot_wire_units,
    max_work,
  })
}

///|
#export_name("clientProgramAdvanceInferObservationVerification")
pub fn client_program_advance_infer_observation_verification(
  active : @model.ModelObservationVerification,
  quantum : Int,
) -> Result[(Bool, Int64), @model.ModelExecutionIssue] {
  @model.advance_model_observation_verification(active, quantum)
}

///|
#export_name("clientProgramCancelInferObservationVerification")
pub fn client_program_cancel_infer_observation_verification(
  active : @model.ModelObservationVerification,
) -> Bool {
  @model.cancel_model_observation_verification(active)
}

///|
#export_name("clientProgramCleanupInferObservationVerification")
pub fn client_program_cleanup_infer_observation_verification(
  active : @model.ModelObservationVerification,
) -> Result[Bool, @model.ModelExecutionIssue] {
  @model.cleanup_model_observation_verification(active)
}

///|
/// Bind to the admitted compiled owner without preparing or compiling again.
/// This retains output custody, not authority to commit a public Result.
#export_name("clientProgramBindInferRun")
pub fn client_program_bind_infer_run(
  active : @infer_host.Execution,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[Unit, @infer_host.InvocationBindingIssue] {
  @infer_host.bind_run(active, compiled, definition)
}

///|
/// Expose the admitted account token, never adapter-authored authority JSON.
#export_name("clientProgramIssueInferDispatchAdmission")
pub fn client_program_issue_infer_dispatch_admission(
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  account : AuthorizationAccount,
  principal : String,
  at : String,
  delegated : AuthorizationDecision?,
  observe_account : () -> AuthorizationAccount,
  observe_at : () -> String,
) -> Result[
  @publication_host.ClientInferDispatchAdmission,
  @publication_host.ClientInferDispatchIssue,
] {
  guard account.state is @authorization.Admitted(configuration) else {
    return Err(@publication_host.Authorization(@authorization.Denied))
  }
  let observe_current : () -> Result[
    (@authorization.AdmittedAccountConfiguration, String),
    @publication_host.ClientInferDispatchIssue,
  ] = () => {
    guard observe_account().state is @authorization.Admitted(current) else {
      return Err(@publication_host.Authorization(@authorization.Denied))
    }
    Ok((current, observe_at()))
  }
  @publication_host.issue_client_infer_dispatch_admission(
    compiled,
    definition,
    configuration,
    principal,
    at,
    delegated_action=match delegated {
      Some(value) => value.action
      None => None
    },
    observe_current~,
  )
}

///|
#export_name("clientProgramBindInferDispatchAdmission")
pub fn client_program_bind_infer_dispatch_admission(
  active : @infer_host.Execution,
  admission : @publication_host.ClientInferDispatchAdmission,
) -> Result[Unit, @infer_host.InvocationBindingIssue] {
  @infer_host.bind_dispatch_admission(active, admission)
}

///|
#export_name("clientProgramInferAttemptEvidence")
pub fn client_program_infer_attempt_evidence(
  active : @infer_host.Execution,
  slot : Int,
) -> Result[@model.ModelAttemptEvidence, @model.ModelExecutionIssue] {
  @infer_host.attempt_evidence(active, slot)
}

///|
#export_name("clientProgramInferStoppedAttemptCount")
pub fn client_program_infer_stopped_attempt_count(
  active : @infer_host.Execution,
) -> Int? {
  @infer_host.stopped_attempt_count(active)
}

///|
#export_name("clientProgramInferAttemptLeaf")
pub fn client_program_infer_attempt_leaf(
  value : @model.ModelAttemptEvidence,
  kind : String,
) -> @publication.RunEvidenceValue? {
  match kind {
    "attempt" => Some(@model.model_attempt_identity(value))
    "accounting" => Some(@model.model_attempt_accounting(value))
    "outcome" => Some(@model.model_attempt_outcome(value))
    "authority" => Some(@model.model_attempt_authority(value))
    _ => None
  }
}

///|
#export_name("clientProgramIssueInferSlotCapture")
pub fn client_program_issue_infer_slot_capture(
  active : @infer_host.Execution,
  slot : Int,
) -> Result[@publication.RunEvidenceValue, @model.ModelExecutionIssue] {
  @infer_host.issued_slot_capture(active, slot)
}

///|
#export_name("clientProgramBindInferInvocation")
pub fn client_program_bind_infer_invocation(
  active : @infer_host.Execution,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  verified : @model.ModelObservationVerification,
  invocation : @publication.PublicationContract,
  data_policy_cid : String,
) -> Result[@infer_host.InvocationBinding, @infer_host.InvocationBindingIssue] {
  @infer_host.bind_invocation(
    active, compiled, definition, verified, invocation, data_policy_cid,
  )
}

///|
#export_name("clientProgramInferInvocationBindingOutput")
pub fn client_program_infer_invocation_binding_output(
  binding : @infer_host.InvocationBinding,
) -> @execution.CompletedOutput? {
  @infer_host.invocation_binding_output(binding)
}

///|
#export_name("clientProgramInferInvocationBindingObservation")
pub fn client_program_infer_invocation_binding_observation(
  binding : @infer_host.InvocationBinding,
) -> @publication.RunEvidenceValue? {
  @infer_host.invocation_binding_observation(binding)
}

///|
#export_name("clientProgramInferInvocationBindingInvocation")
pub fn client_program_infer_invocation_binding_invocation(
  binding : @infer_host.InvocationBinding,
) -> @publication.PublicationContract? {
  @infer_host.invocation_binding_invocation(binding)
}

///|
#export_name("clientProgramReleaseInferInvocationBinding")
pub fn client_program_release_infer_invocation_binding(
  binding : @infer_host.InvocationBinding,
) -> Bool {
  @infer_host.release_invocation_binding(binding)
}

///|
#export_name("clientProgramAcquireInferOutcomes")
pub fn client_program_acquire_infer_outcomes(
  active : @infer_host.Execution,
) -> @model.ModelOutcomeRead? {
  @infer_host.acquire_outcomes(active)
}

///|
#export_name("clientProgramInferOutcomesAccepted")
pub fn client_program_infer_outcomes_accepted(
  read : @model.ModelOutcomeRead,
) -> Bool {
  @model.model_outcomes_accepted(read)
}

///|
#export_name("clientProgramInferOutcomesCount")
pub fn client_program_infer_outcomes_count(
  read : @model.ModelOutcomeRead,
) -> Int? {
  @model.model_outcomes_count(read)
}

///|
#export_name("clientProgramInferOutcomesCall")
pub fn client_program_infer_outcomes_call(
  read : @model.ModelOutcomeRead,
  slot : Int,
) -> @publication.RunEvidenceValue? {
  @model.model_outcomes_call_at(read, slot)
}

///|
#export_name("clientProgramInferOutcomesOutcome")
pub fn client_program_infer_outcomes_outcome(
  read : @model.ModelOutcomeRead,
  slot : Int,
) -> String? {
  @model.model_outcomes_outcome(read, slot)
}

///|
#export_name("clientProgramReleaseInferOutcomes")
pub fn client_program_release_infer_outcomes(
  read : @model.ModelOutcomeRead,
) -> Bool {
  @model.release_model_outcomes(read)
}

///|
/// The installed capture owner reads the actual accepted call inventory;
/// successful bundle records are not a substitute for this inventory.
#export_name("clientProgramInferCaptureCallCount")
pub fn client_program_infer_capture_call_count(
  capture : @model.VerifiedModelCapture,
) -> Int? {
  @model.verified_model_capture_call_count(capture)
}

///|
#export_name("clientProgramInferCaptureOutcome")
pub fn client_program_infer_capture_outcome(
  capture : @model.VerifiedModelCapture,
  slot : Int,
) -> String? {
  @model.verified_model_capture_outcome(capture, slot)
}

///|
#export_name("clientProgramInferCaptureCall")
pub fn client_program_infer_capture_call(
  capture : @model.VerifiedModelCapture,
  slot : Int,
) -> @publication.RunEvidenceValue? {
  @model.verified_model_capture_call_at(capture, slot)
}

///|
/// This checks exact execution references, not external attempt, authority or
/// accounting evidence. Those remain the installing capture owner's duties.
#export_name("clientProgramBindInferSlotCapture")
pub fn client_program_bind_infer_slot_capture(
  capture : @model.VerifiedModelCapture,
  slot : Int,
  record : @publication.RunEvidenceValue,
) -> Result[@publication.BoundModelSlotCapture, @model.ModelExecutionIssue] {
  @model.bind_verified_model_slot_capture(capture, slot, record)
}

///|
/// The existing Store must authenticate and confirm the expected holding
/// before these bytes are offered to the common record reader. This bridge
/// performs protocol admission, not execution or publication authorization.
#export_name("clientProgramReadInferCaptureBundle")
pub fn client_program_read_infer_capture_bundle(
  wire : String,
  expected_cid : String,
) -> Result[
  @publication.ModelCaptureBundleRead,
  @publication.RunEvidenceValueIssue,
] {
  @publication.read_model_capture_bundle(wire, expected_cid, 100000, 20000, 100)
}

///|
#export_name("clientProgramStartRestoredInferReplay")
pub fn client_program_start_restored_infer_replay(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  graph : @publication_host.ClientInferPlanGraph,
  registry : String,
  values : String,
  capture : @publication.ModelCaptureBundleRead,
  fragment : String,
  ordered : String,
) -> Result[@infer_host.Execution, @infer_host.Issue] {
  @infer_host.start_restored_replay(
    prepared,
    step,
    registry,
    values,
    capture,
    @infer_host.standard_limits(),
    graph,
    fragment_body=Some(fragment),
    ordered_body=Some(ordered),
  )
}

///|
#export_name("clientProgramReleaseInferCaptureBundle")
pub fn client_program_release_infer_capture_bundle(
  capture : @publication.ModelCaptureBundleRead,
) -> Bool {
  @publication.release_model_capture_bundle_read(capture)
}

///|
/// The capture owner authenticates and confirms each private holding first.
/// This is structural admission, not permission to publish or dispatch.
#export_name("clientProgramReadInferSlotReplay")
pub fn client_program_read_infer_slot_replay(
  observation : @publication.RunEvidenceValue,
  records : Array[@publication.RunEvidenceValue],
  bundle : @publication.ModelCaptureBundleRead,
  max_slots : Int,
  max_slot_wire_units : Int,
) -> Result[@model.ModelSlotReplayRead, @model.ModelExecutionIssue] {
  @model.read_model_slot_replay(
    observation, records, bundle, max_slots, max_slot_wire_units,
  )
}

///|
/// Imported leaves are observations, not a newly issued proof or grant.
#export_name("clientProgramInferAttemptRecords")
pub fn client_program_infer_attempt_records(
  attempt : @publication.RunEvidenceValue,
  accounting : @publication.RunEvidenceValue,
  outcome : @publication.RunEvidenceValue,
  authority : @publication.RunEvidenceValue,
) -> @model.ModelAttemptRecords {
  { attempt, accounting, outcome, authority, }
}

///|
/// The installing Store owner authenticates the saved holdings first. Replay
/// verifies the original admitted Run and complete leaf chain per slot.
#export_name("clientProgramReadVerifiedInferSlotReplay")
pub fn client_program_read_verified_infer_slot_replay(
  observation : @publication.RunEvidenceValue,
  records : Array[@publication.RunEvidenceValue],
  bundle : @publication.ModelCaptureBundleRead,
  proofs : Array[@model.ModelAttemptRecords],
  saved : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  max_slots : Int,
  max_slot_wire_units : Int,
) -> Result[@model.ModelSlotReplayRead, @model.ModelExecutionIssue] {
  if @publication_host.check_client_compiled_run_definition(saved, definition)
    is Err(_) {
    return Err(@model.OutputIdentity)
  }
  @model.read_verified_model_slot_replay(
    observation,
    records,
    bundle,
    proofs,
    @publication_host.client_compiled_run_admission(saved),
    definition,
    max_slots,
    max_slot_wire_units,
  )
}

///|
#export_name("clientProgramStartRestoredInferSlotReplay")
pub fn client_program_start_restored_infer_slot_replay(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  graph : @publication_host.ClientInferPlanGraph,
  registry : String,
  values : String,
  read : @model.ModelSlotReplayRead,
  fragment : String,
  ordered : String,
) -> Result[@infer_host.Execution, @infer_host.Issue] {
  @infer_host.start_restored_slot_replay(
    prepared,
    step,
    registry,
    values,
    read,
    @infer_host.standard_limits(),
    graph,
    fragment_body=Some(fragment),
    ordered_body=Some(ordered),
  )
}

///|
#export_name("clientProgramReleaseInferSlotReplay")
pub fn client_program_release_infer_slot_replay(
  read : @model.ModelSlotReplayRead,
) -> Bool {
  @model.release_model_slot_replay(read)
}

///|
#export_name("clientProgramInferExecutionRestoring")
pub fn client_program_infer_execution_restoring(
  active : @infer_host.Execution,
) -> Bool {
  @infer_host.restoring(active)
}

///|
#export_name("clientProgramReleaseInferCapture")
pub fn client_program_release_infer_capture(
  capture : @model.VerifiedModelCapture,
) -> Bool {
  @model.release_verified_model_capture(capture)
}

///|
#export_name("clientProgramStartInferCaptureExport")
pub fn client_program_start_infer_capture_export(
  capture : @model.VerifiedModelCapture,
  max_bytes : Int,
  max_work : Int,
) -> Result[@model.ModelCaptureExport, @model.ModelExecutionIssue] {
  @model.start_model_capture_export(capture, {
    max_bytes,
    max_nodes: 20000,
    max_depth: 100,
    max_chunk_bytes: 65536,
    max_work,
  })
}

///|
#export_name("clientProgramAdvanceInferCaptureExport")
pub fn client_program_advance_infer_capture_export(
  active : @model.ModelCaptureExport,
  quantum : Int,
) -> Result[(Bool, String, Int64), @model.ModelExecutionIssue] {
  @model.advance_model_capture_export(active, quantum)
}

///|
#export_name("clientProgramInferCaptureExportIdentity")
pub fn client_program_infer_capture_export_identity(
  active : @model.ModelCaptureExport,
) -> String? {
  @model.model_capture_export_identity(active)
}

///|
#export_name("clientProgramCancelInferCaptureExport")
pub fn client_program_cancel_infer_capture_export(
  active : @model.ModelCaptureExport,
) -> Bool {
  @model.cancel_model_capture_export(active)
}

///|
#export_name("clientProgramInferCaptureExportResponsePending")
pub fn client_program_infer_capture_export_response_pending(
  active : @model.ModelCaptureExport,
) -> Bool {
  @model.model_capture_export_response_pending(active)
}

///|
#export_name("clientProgramCleanupInferCaptureExport")
pub fn client_program_cleanup_infer_capture_export(
  active : @model.ModelCaptureExport,
) -> Result[Bool, @model.ModelExecutionIssue] {
  @model.cleanup_model_capture_export(active)
}

///|
/// Start one owned physical operation only after the Host admits model access.
/// Preparation, dispatch and output share the original checked Program owner.
#export_name("clientProgramStartInferExecution")
pub fn client_program_start_infer_execution(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  registry : String,
  values : String,
  provider : @model.ModelProvider,
  fixed_request_cid : String,
) -> Result[@infer_host.Execution, @infer_host.Issue] {
  @infer_host.start(
    prepared,
    step,
    registry,
    values,
    provider,
    fixed_request_cid,
    @infer_host.standard_limits(),
  )
}

///|
#export_name("clientProgramAdvanceInferExecution")
pub fn client_program_advance_infer_execution(
  active : @infer_host.Execution,
  quantum : Int,
) -> Result[@infer_host.Poll, @infer_host.Issue] {
  @infer_host.advance(active, quantum)
}

///|
#export_name("clientProgramInferExecutionOutput")
pub fn client_program_infer_execution_output(
  value : @infer_host.Poll,
) -> @execution.CompletedOutput? {
  @infer_host.completed(value)
}

///|
#export_name("clientProgramInferExecutionStopped")
pub fn client_program_infer_execution_stopped(
  active : @infer_host.Execution,
) -> Bool {
  @infer_host.execution_stopped(active)
}

///|
#export_name("clientProgramInferExecutionPollKind")
pub fn client_program_infer_execution_poll_kind(
  value : @infer_host.Poll,
) -> String {
  @infer_host.poll_kind(value)
}

///|
#export_name("clientProgramInferExecutionPollIssue")
pub fn client_program_infer_execution_poll_issue(
  value : @infer_host.Poll,
) -> @infer_host.Issue? {
  @infer_host.poll_issue(value)
}

///|
#export_name("clientProgramInferExecutionHandoffPending")
pub fn client_program_infer_execution_handoff_pending(
  active : @infer_host.Execution,
) -> Bool {
  @infer_host.handoff_pending(active)
}

///|
#export_name("clientProgramInferRequestPreflightPending")
pub fn client_program_infer_request_preflight_pending(
  active : @infer_host.Execution,
) -> Bool {
  @infer_host.request_preflight_pending(active)
}

///|
#export_name("clientProgramInferIdentityPending")
pub fn client_program_infer_identity_pending(
  active : @infer_host.Execution,
) -> Bool {
  @infer_host.identity_pending(active)
}

///|
#export_name("clientProgramInferExecutionCapture")
pub fn client_program_infer_execution_capture(
  active : @infer_host.Execution,
) -> @model.ModelCaptureBundle? {
  @infer_host.capture(active)
}

///|
#export_name("clientProgramCancelInferExecution")
pub fn client_program_cancel_infer_execution(
  active : @infer_host.Execution,
) -> Bool {
  @infer_host.cancel(active)
}

///|
#export_name("clientProgramCleanupInferExecution")
pub fn client_program_cleanup_infer_execution(
  active : @infer_host.Execution,
) -> Result[Bool, @infer_host.Issue] {
  @infer_host.cleanup(active)
}

///|
#export_name("clientProgramAcquireInferOutput")
pub fn client_program_acquire_infer_output(
  active : @infer_host.Execution,
) -> @infer_host.OutputUse? {
  @infer_host.acquire_output(active)
}

///|
#export_name("clientProgramInferOutputUse")
pub fn client_program_infer_output_use(
  value : @infer_host.OutputUse,
) -> @execution.CompletedOutput? {
  @infer_host.output(value)
}

///|
#export_name("clientProgramReleaseInferOutput")
pub fn client_program_release_infer_output(
  value : @infer_host.OutputUse,
) -> Bool {
  @infer_host.release_output(value)
}

///|
/// Admit compiler dependency material under the normal prepared Program.
#export_name("clientProgramReadInferModelExecution")
pub fn client_program_read_infer_model_execution(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  body : String,
  expected_cid : String,
) -> Result[
  @check_environment.ModelExecutionContract,
  @publication_host.ClientInferPlanGraphIssue,
] {
  @publication_host.read_prepared_client_infer_model_execution(
    prepared,
    step,
    @utf8.encode(body),
    expected_cid,
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 10000, },
    1000000,
  )
}

///|
/// Diagnostic reader only. Preserve the original typed issue as the cause;
/// this label is neither an evidence body nor a new public failure category.
#export_name("clientProgramInferModelExecutionIssueKind")
pub fn client_program_infer_model_execution_issue_kind(
  issue : @publication_host.ClientInferPlanGraphIssue,
) -> String {
  match issue {
    @publication_host.Execution(failure) =>
      match failure.kind {
        @check_environment.IdentityMismatch => "identity_mismatch"
        @check_environment.ReferenceMismatch => "reference_mismatch"
        @check_environment.InvalidBody => "invalid_body"
        @check_environment.BodyLimit | @check_environment.WorkLimit => "limit"
        _ => "invalid_execution"
      }
    _ => "unsupported_program"
  }
}

///|
#export_name("clientProgramReadInferModelDependencies")
pub fn client_program_read_infer_model_dependencies(
  execution : @check_environment.ModelExecutionContract,
  prompt : String?,
  retry : String?,
  backoff : String?,
) -> Result[
  @check_environment.SingleAttemptModelDependencies,
  @check_environment.ModelDependencyIssue,
] {
  @check_environment.read_single_attempt_model_dependencies(
    execution,
    prompt.map(value => @utf8.encode(value)),
    retry.map(value => @utf8.encode(value)),
    backoff.map(value => @utf8.encode(value)),
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 10000, },
    1000000,
  )
}

///|
#export_name("clientProgramInferDependencyReferences")
pub fn client_program_infer_dependency_references(
  execution : @check_environment.ModelExecutionContract,
) -> (String, String, String) {
  (
    @check_environment.model_task_prompt_cid(
      @check_environment.model_execution_task(execution),
    ),
    @check_environment.model_execution_retry_cid(execution),
    @check_environment.model_execution_backoff_cid(execution),
  )
}

///|
#export_name("clientProgramInferProviderId")
pub fn client_program_infer_provider_id(
  execution : @check_environment.ModelExecutionContract,
) -> String {
  @check_environment.model_task_connector(
    @check_environment.model_execution_task(execution),
  )
}

///|
#export_name("clientProgramInferModelDependencyIssueKind")
pub fn client_program_infer_model_dependency_issue_kind(
  issue : @check_environment.ModelDependencyIssue,
) -> String {
  match issue {
    @check_environment.Missing(_) => "missing_body"
    @check_environment.UnsupportedPolicy(_) => "unsupported_policy"
    @check_environment.Body(_, failure) =>
      match failure.kind {
        @check_environment.IdentityMismatch => "identity_mismatch"
        @check_environment.InvalidBody => "invalid_body"
        @check_environment.BodyLimit | @check_environment.WorkLimit => "limit"
        _ => "invalid_dependency"
      }
  }
}

///|
/// Provider registration supplies the interpretation; common owners bind it
/// to the selected Task and dependencies before Run or physical dispatch.
#export_name("clientProgramAdmitModelProvider")
pub fn client_program_admit_model_provider(
  provider : @model.ModelProvider,
  execution : @check_environment.ModelExecutionContract,
  dependencies : @check_environment.SingleAttemptModelDependencies,
  validate : (String, String, String) -> Bool,
) -> Result[@model.AdmittedModelProvider, @model.ModelProviderAdmissionIssue] {
  @model.admit_model_provider(provider, execution, dependencies, (task, prompt) => {
    let writer = @encode.writer(100000, 10000, 100) catch { _ => return false }
    let emitted = @check_environment.emit_model_prompt_payload(prompt, writer) catch {
      _ => return false
    }
    if !emitted {
      return false
    }
    let wire = @encode.finish(writer) catch { _ => return false }
    let (_, _, task_cid) = @check_environment.model_task_identity(task)
    validate(task_cid, @check_environment.model_task_model_selector(task), wire)
  })
}

///|
#export_name("clientProgramModelProviderAdmissionIssueKind")
pub fn client_program_model_provider_admission_issue_kind(
  issue : @model.ModelProviderAdmissionIssue,
) -> String {
  match issue {
    @model.ForeignDependencies => "foreign_dependencies"
    @model.ForeignProvider => "foreign_provider"
    @model.UnsupportedPrompt => "unsupported_prompt"
  }
}

///|
#export_name("clientProgramAdmittedModelProvider")
pub fn client_program_admitted_model_provider(
  value : @model.AdmittedModelProvider,
  execution : @check_environment.ModelExecutionContract,
) -> @model.ModelProvider? {
  @model.admitted_model_provider_for(value, execution)
}

///|
/// The graph binds references but does not authorize a Run or a model call.
#export_name("clientProgramInferPlanGraph")
pub fn client_program_infer_plan_graph(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  execution : @check_environment.ModelExecutionContract,
  limits_cid : String,
  egress_cid : String,
) -> Result[
  @publication_host.ClientInferPlanGraph,
  @publication_host.ClientInferPlanGraphIssue,
] {
  @publication_host.issue_prepared_client_infer_plan_graph(
    prepared,
    step,
    execution,
    limits_cid,
    egress_cid,
    @publication_host.client_standard_values_sequence_limits(),
    100000,
    10000,
    100,
  )
}

///|
#export_name("clientProgramAdmitInferEgress")
pub fn client_program_admit_infer_egress(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  execution : @check_environment.ModelExecutionContract,
  observe : () -> (String, String, Bool, Bool)?,
) -> Result[
  @publication_host.ClientInferEgressAdmission,
  @publication_host.ClientInferEgressIssue,
] {
  @publication_host.admit_prepared_client_infer_egress(
    prepared,
    step,
    execution,
    () => client_infer_egress_observation(observe()),
  )
}

///|
fn client_infer_egress_observation(
  observation : (String, String, Bool, Bool)?,
) -> @publication_host.ClientInferEgressObservation? {
  guard observation is Some((name, region, provider_retention, training_use)) else {
    return None
  }
  let classification = match name {
    "public" => @check_environment.Public
    "internal" => @check_environment.Internal
    "confidential" => @check_environment.Confidential
    "restricted" => @check_environment.Restricted
    "unknown" => @check_environment.Unknown
    _ => return None
  }
  Some({ classification, region, provider_retention, training_use, })
}

///|
#export_name("clientProgramInstalledInferPlanGraph")
pub fn client_program_installed_infer_plan_graph(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  execution : @check_environment.ModelExecutionContract,
) -> Result[
  @publication_host.ClientInferPlanGraph,
  @publication_host.ClientInferPlanGraphIssue,
] {
  @publication_host.issue_installed_client_infer_plan_graph(
    prepared,
    step,
    execution,
    @publication_host.client_standard_values_sequence_limits(),
    100000,
    10000,
    100,
  )
}

///|
#export_name("clientProgramModelPrivateHoldingCid")
pub fn client_program_model_private_holding_cid(
  definition : @publication.PublicationContract,
  store : String,
  role : String,
  slot : Int,
) -> String? {
  @publication.model_private_holding_cid(definition, store, role, slot)
}

///|
#export_name("clientProgramBindInferEgress")
pub fn client_program_bind_infer_egress(
  active : @infer_host.Execution,
  admission : @publication_host.ClientInferEgressAdmission,
) -> Result[Unit, @infer_host.Issue] {
  @infer_host.bind_egress_admission(active, admission)
}

///|
#export_name("clientProgramInferEgressIssueKind")
pub fn client_program_infer_egress_issue_kind(
  issue : @publication_host.ClientInferEgressIssue,
) -> String {
  match issue {
    @publication_host.ForeignOwner => "foreign_owner"
    @publication_host.MissingObservation => "missing_observation"
    @publication_host.UnknownClassification => "unknown_classification"
    @publication_host.ClassificationDenied => "classification_denied"
    @publication_host.RegionDenied => "region_denied"
    @publication_host.RetentionDenied => "retention_denied"
    @publication_host.TrainingDenied => "training_denied"
    @publication_host.ChangedObservation => "changed_observation"
    @publication_host.InputPolicyUnavailable => "input_policy_unavailable"
  }
}

///|
#export_name("clientProgramInferPlanGraphWire")
pub fn client_program_infer_plan_graph_wire(
  value : @publication_host.ClientInferPlanGraph,
) -> String {
  @publication_host.client_infer_plan_graph_wire(value)
}

///|
#export_name("clientProgramInferPlanRequestWire")
pub fn client_program_infer_plan_request_wire(
  value : @publication_host.ClientInferPlanGraph,
) -> String {
  @publication_host.client_infer_plan_graph_request_wire(value)
}

///|
pub(all) enum ClientProgramInferMaterialBridgeIssue {
  Manifests(@publication_host.ClientCompilationManifestIssue)
  Material(@publication_host.ClientExecutionMaterialIssue)
}

///|
/// Compile profile/template and Result material under the original owner.
/// This does not issue a runnable Plan or authorize a provider dispatch.
#export_name("clientProgramInferExecutionMaterial")
pub fn client_program_infer_execution_material(
  prepared : @publication_host.PreparedClientProgram,
  graph : @publication_host.ClientInferPlanGraph,
) -> Result[
  @publication_host.ClientExecutionMaterial,
  ClientProgramInferMaterialBridgeIssue,
] {
  let manifests = match
    @publication_host.admit_client_compilation_manifests(
      @check_environment.compiler_grammar_manifest_wire(),
      @check_environment.compiler_barrier_contract_manifest_wire(),
      100000,
      10000,
      100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
  }
  @publication_host.issue_prepared_client_infer_execution_material(
    prepared, graph, manifests, 100000, 10000, 100,
  ).map_err(issue => Material(issue))
}

///|
#export_name("clientProgramInferExecutionMaterialWire")
pub fn client_program_infer_execution_material_wire(
  value : @publication_host.ClientExecutionMaterial,
) -> String {
  @publication_host.client_execution_material_wire(value)
}

///|
#export_name("clientProgramInferExecutionMaterialTemplateWire")
pub fn client_program_infer_execution_material_template_wire(
  value : @publication_host.ClientExecutionMaterial,
) -> String {
  @publication_host.client_execution_material_template_wire(value)
}

///|
/// The acquisition compiler uses the same checked pure prefix as execution.
/// This fragment alone is not a runnable Infer Plan.
#export_name("clientProgramInferPrefixFragment")
pub fn client_program_infer_prefix_fragment(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
) -> Result[
  @publication_host.ClientTaskFragmentNode,
  @publication_host.ClientTaskFragmentIssue,
] {
  @publication_host.issue_prepared_client_infer_prefix_fragment(
    prepared,
    task,
    step,
    @publication_host.client_standard_values_sequence_limits(),
    100000,
    10000,
    100,
  )
}

///|
/// Begin normal checked input execution, not a capture assembled by a caller.
#export_name("clientProgramStartInferInput")
pub fn client_program_start_infer_input(
  prepared : @publication_host.PreparedClientProgram,
  registry_body : String,
  values_body : String,
  step : Int,
) -> @client_local_host.ClientInferInputExecution? {
  let values : @execution.ValueLimits = {
    max_nodes: 20000,
    max_depth: 100,
    max_text_bytes: 500000,
    max_work: 20000000,
  }
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 100,
      metadata_entries: 10000,
      retained_entries: 10000,
      operation_entries: 10000,
      input_values: values,
      output_values: values,
    },
    max_work: values.max_work,
    max_frames: 100,
  }
  match
    @client_local_host.start_client_infer_input(
      prepared,
      0,
      step,
      registry_body,
      values_body,
      execution,
      {
        max_work: values.max_work,
        max_bytes: values.max_text_bytes,
        max_nodes: values.max_nodes,
        max_depth: values.max_depth,
      },
      {
        max_items: 100,
        max_work: values.max_work,
        max_frames: 100,
        max_workspace_slots: 10000,
        values: {
          max_nodes: values.max_nodes,
          max_depth: values.max_depth,
          max_text_bytes: values.max_text_bytes,
        },
        logical: {
          max_input_rows: 100L,
          max_value_bytes: 10000L,
          max_live_value_bytes: 100000L,
          max_work: values.max_work.to_int64(),
        },
      },
    ) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
#export_name("clientProgramAdvanceInferInput")
pub fn client_program_advance_infer_input(
  active : @client_local_host.ClientInferInputExecution,
  quantum : Int,
) -> Result[
  @client_local_host.ClientInferInputPoll,
  @client_local_host.ClientInferInputIssue,
] {
  @client_local_host.advance_client_infer_input(active, quantum)
}

///|
#export_name("clientProgramInferInputRows")
pub fn client_program_infer_input_rows(
  poll : @client_local_host.ClientInferInputPoll,
) -> @execution.PreparedInferRows? {
  match poll {
    @client_local_host.Complete(rows, ..) => Some(rows)
    _ => None
  }
}

///|
#export_name("clientProgramCancelInferInput")
pub fn client_program_cancel_infer_input(
  active : @client_local_host.ClientInferInputExecution,
) -> Bool {
  @client_local_host.cancel_client_infer_input(active)
}

///|
#export_name("clientProgramCleanupInferInput")
pub fn client_program_cleanup_infer_input(
  active : @client_local_host.ClientInferInputExecution,
) -> Result[Bool, @client_local_host.ClientInferInputIssue] {
  @client_local_host.cleanup_client_infer_input(active)
}

///|
/// Trusted Host registration. A returned response is admitted again against
/// the installed ModelTask; the Program cannot choose the callback.
#export_name("clientProgramInstallModelProvider")
pub fn client_program_install_model_provider(
  provider_id : String,
  invoke : (@model.ModelRequest) -> @model.ModelResponse?,
) -> @model.ModelProvider? {
  match
    @model.install_model_provider(provider_id, request => {
      match invoke(request) {
        Some(response) => Ok(response)
        None => Err(@model.ProviderError)
      }
    }) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
#export_name("clientProgramModelRequestInput")
pub fn client_program_model_request_input(
  request : @model.ModelRequest,
  role : String,
) -> String? {
  for (name, value) in request.inputs {
    if role != name {
      continue
    }
    let writer = @encode.writer(65536, 10000, 64) catch { _ => return None }
    @admitted.emit_checked_wire_value(value, writer) catch {
      _ => return None
    }
    return Some(@encode.finish(writer)) catch { _ => None }
  }
  None
}

///|
/// Physical response decoding is bounded and task-typed. Provider metadata
/// is observation, not a contract or execution permit supplied by a Program.
#export_name("clientProgramModelResponse")
pub fn client_program_model_response(
  request : @model.ModelRequest,
  value_body : String,
  provider_model : String,
  provider_request_id : String,
  input_tokens : Int64,
  output_tokens : Int64,
  observed_at : String,
) -> @model.ModelResponse? {
  let source = match
    @source.parse_json(value_body, {
      max_input_bytes: 65536,
      max_nodes: 10000,
      max_depth: 64,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: 10000,
      max_depth: 64,
      max_string_bytes: 65536,
      max_total_string_bytes: 65536,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  let checked = match
    @admitted.admit(
      @check_environment.model_task_output(request.task),
      cursor,
      { max_nodes: 10000, max_depth: 64, max_text_bytes: 65536, },
    ) {
    Ok(value) => value
    Err(_) => return None
  }
  Some({
    value: checked.value,
    provider_model,
    provider_request_id,
    input_tokens,
    output_tokens,
    observed_at,
  })
}

///|
#export_name("clientProgramStartModelExecution")
pub fn client_program_start_model_execution(
  rows : @execution.PreparedInferRows,
  provider : @model.ModelProvider,
  fixed_request_cid : String,
) -> Result[@model.ModelExecution, @model.ModelExecutionIssue] {
  @model.start_model_execution(rows, provider, fixed_request_cid, {
    max_items: 100,
    max_work: 10000,
    max_request_bytes: 65536L,
    max_response_bytes: 65536L,
    value_limits: { max_nodes: 10000, max_depth: 64, max_text_bytes: 65536, },
    ledger: {
      planning_work: 10000,
      attempts: 100,
      holdings: 100,
      transfer_bytes: 13107200L,
      retained_bytes: 6553600L,
      execution_bytes: 6553600L,
    },
  })
}

///|
#export_name("clientProgramAdvanceModelExecution")
pub fn client_program_advance_model_execution(
  active : @model.ModelExecution,
  quantum : Int,
) -> Result[@model.ModelObservation, @model.ModelExecutionIssue] {
  @model.advance_model_execution(active, quantum)
}

///|
#export_name("clientProgramModelCapture")
pub fn client_program_model_capture(
  poll : @model.ModelObservation,
) -> @model.ModelCaptureBundle? {
  match poll {
    @model.Completed(bundle, _, _) => Some(bundle)
    _ => None
  }
}

///|
#export_name("clientProgramModelCaptureJson")
pub fn client_program_model_capture_json(
  bundle : @model.ModelCaptureBundle,
) -> String? {
  @model.model_capture_bundle_json(bundle, 100000, 10000, 64)
}

///|
#export_name("clientProgramInferInvocationEvidence")
pub fn client_program_infer_invocation_evidence(
  active : @infer_host.Execution,
  slot : Int,
) -> @publication.RunEvidenceValue? {
  @infer_host.invocation_evidence(active, slot)
}

///|
#export_name("clientProgramInferObservationPending")
pub fn client_program_infer_observation_pending(
  active : @infer_host.Execution,
) -> Bool {
  @infer_host.sealing_observation(active)
}

///|
#export_name("clientProgramCleanupModelExecution")
pub fn client_program_cleanup_model_execution(
  active : @model.ModelExecution,
) -> Result[Bool, @model.ModelExecutionIssue] {
  @model.cleanup_model_execution(active)
}

///|
#export_name("clientProgramCancelModelExecution")
pub fn client_program_cancel_model_execution(
  active : @model.ModelExecution,
) -> Bool {
  @model.request_model_cancel(active)
}

///|
#export_name("clientProgramReplayModelCapture")
pub fn client_program_replay_model_capture(
  rows : @execution.PreparedInferRows,
  fixed_request_cid : String,
  bundle : @model.ModelCaptureBundle,
) -> Bool {
  @model.replay_model_capture_rows(rows, fixed_request_cid, bundle) is Ok(_)
}

///|
#export_name("clientProgramStartModelOutput")
pub fn client_program_start_model_output(
  input : @client_local_host.ClientInferInputExecution,
  rows : @execution.PreparedInferRows,
  model : @model.ModelExecution,
) -> Result[@model.ModelOutputPreparation, @model.ModelExecutionIssue] {
  guard @client_local_host.client_infer_completion_preparation(input, rows)
    is Some(completion) else {
    return Err(@model.OutputIdentity)
  }
  @model.start_model_output_preparation(
    model,
    completion,
    100,
    {
      max_nodes: 20000,
      max_text_bytes: 500000,
      max_depth: 100,
      max_work: 20000000,
    },
    20000000,
    10000,
  )
}

///|
#export_name("clientProgramAdvanceModelOutput")
pub fn client_program_advance_model_output(
  value : @model.ModelOutputPreparation,
  quantum : Int,
) -> Result[@execution.AdmittedOutputPoll, @model.ModelExecutionIssue] {
  @model.advance_model_output_preparation(value, quantum)
}

///|
#export_name("clientProgramCompleteModelOutput")
pub fn client_program_complete_model_output(
  value : @model.ModelOutputPreparation,
) -> Result[@execution.CompletedOutput, @model.ModelExecutionIssue] {
  @model.complete_model_output(value)
}

///|
#export_name("clientProgramCancelModelOutput")
pub fn client_program_cancel_model_output(
  value : @model.ModelOutputPreparation,
) -> Bool {
  @model.cancel_model_output_preparation(value)
}

///|
#export_name("clientProgramCleanupModelOutput")
pub fn client_program_cleanup_model_output(
  value : @model.ModelOutputPreparation,
) -> Result[Bool, @model.ModelExecutionIssue] {
  @model.cleanup_model_output_preparation(value)
}

///|
/// An issued Invocation, not an adapter-authored output, owns this export.
#export_name("clientProgramInferPublicationBegin")
pub fn client_program_infer_publication_begin(
  binding : @infer_host.InvocationBinding,
  result : Int,
) -> Result[@infer_host.ResultPublication, @infer_host.ResultPublicationIssue] {
  @infer_host.start_result_publication(
    binding,
    result,
    client_infer_result_limits(),
  )
}

///|
#export_name("clientProgramInferPublicationSelection")
pub fn client_program_infer_publication_selection(
  value : @infer_host.ResultPublication,
) -> @publication_host.ClientResultTransformation? {
  @infer_host.result_publication_selection(value)
}

///|
#export_name("clientProgramInferPublicationAdvance")
pub fn client_program_infer_publication_advance(
  value : @infer_host.ResultPublication,
  quantum : Int,
) -> Result[(Bool, Int), @infer_host.ResultPublicationIssue] {
  @infer_host.advance_result_publication(value, quantum)
}

///|
#export_name("clientProgramInferPublicationFinish")
pub fn client_program_infer_publication_finish(
  value : @infer_host.ResultPublication,
) -> Result[
  @publication_host.PublicationOutputExport,
  @infer_host.ResultPublicationIssue,
] {
  @infer_host.finish_result_publication(value)
}

///|
/// Reuse the standard Store export bridge without reconstructing output rows.
/// The ResultPublication owner retains the underlying export until Store I/O
/// and any cleanup retry have settled.
#export_name("clientProgramInferPublicationStoreExport")
pub fn client_program_infer_publication_store_export(
  value : @infer_host.ResultPublication,
) -> Result[StrategyHostOutputExport, @infer_host.ResultPublicationIssue] {
  @infer_host.finish_result_publication(value).map(core => {
    core,
    managed_import: None,
  })
}

///|
#export_name("clientProgramInferPublicationCancel")
pub fn client_program_infer_publication_cancel(
  value : @infer_host.ResultPublication,
) -> Bool {
  @infer_host.cancel_result_publication(value)
}

///|
#export_name("clientProgramInferPublicationRelease")
pub fn client_program_infer_publication_release(
  value : @infer_host.ResultPublication,
) -> Bool {
  @infer_host.release_result_publication(value)
}

///|
#export_name("clientProgramInferResultName")
pub fn client_program_infer_result_name(
  value : @publication_host.ClientResultTransformation,
) -> String {
  @publication_host.client_result_transformation_name(value)
}

///|
#export_name("clientProgramInferResultTask")
pub fn client_program_infer_result_task(
  value : @publication_host.ClientResultTransformation,
) -> Int {
  @publication_host.client_result_transformation_task(value)
}

///|
#export_name("clientProgramInferResultDefinition")
pub fn client_program_infer_result_definition(
  value : @publication_host.ClientResultTransformation,
) -> @publication.PublicationContract {
  @publication_host.client_result_transformation_definition(value)
}

///|
/// Select the existing Result transform under the original Program owner.
/// This is an export, not Run acceptance or a committed Named Result index.
#export_name("clientProgramInferResultExportBegin")
pub fn client_program_infer_result_export_begin(
  prepared : @publication_host.PreparedClientProgram,
  result : Int,
  output : @execution.CompletedOutput,
) -> Result[
  @publication_host.ClientResultTransformationPreparation,
  @publication_host.ClientResultTransformationIssue,
] {
  let selection = match
    @publication_host.prepare_client_result_transformation(
      prepared, result, 500000, 20000, 100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @publication_host.start_client_result_transformation(
    selection,
    output,
    client_infer_result_limits(),
  )
}

///|
/// Shared installed envelope for both existing component exports and issued
/// Invocation exports. This does not grant permission to commit a Result.
fn client_infer_result_limits() -> @publication_host.PublicationOutputExportLimits {
  let wire : @execution.RowWireLimits = {
    max_columns: 256,
    max_order_work: 20000000,
    max_bytes: 500000,
    max_nodes: 20000,
    max_depth: 100,
  }
  {
    max_result_fields: 256,
    max_result_mapping_work: 20000000,
    max_result_order_work: 20000000,
    max_result_workspace_entries: 10000,
    max_rows: 100,
    values: {
      max_nodes: 20000,
      max_text_bytes: 500000,
      max_depth: 100,
      max_work: 20000000,
    },
    payload_wire: wire,
    logical_wire: wire,
    schema: {
      max_fields: 256,
      max_bytes: 500000,
      max_nodes: 20000,
      max_depth: 100,
    },
    max_batch_bytes: 500000,
  }
}

///|
#export_name("clientProgramInferResultExportAdvance")
pub fn client_program_infer_result_export_advance(
  value : @publication_host.ClientResultTransformationPreparation,
  quantum : Int,
) -> Result[(Bool, Int), @publication_host.ClientResultTransformationIssue] {
  value.advance(quantum)
}

///|
#export_name("clientProgramInferResultExportFinish")
pub fn client_program_infer_result_export_finish(
  value : @publication_host.ClientResultTransformationPreparation,
) -> Result[
  @publication_host.PublicationOutputExport,
  @publication_host.ClientResultTransformationIssue,
] {
  value.finish()
}

///|
#export_name("clientProgramInferResultExportNext")
pub fn client_program_infer_result_export_next(
  value : @publication_host.PublicationOutputExport,
) -> Result[String?, @publication_host.PublicationOutputExportIssue] {
  value.next()
}

///|
#export_name("clientProgramInferResultExportSeal")
pub fn client_program_infer_result_export_seal(
  value : @publication_host.PublicationOutputExport,
) -> Result[String, @publication_host.PublicationOutputExportIssue] {
  value.finish()
}

///|
#export_name("clientProgramInferResultExportClose")
pub fn client_program_infer_result_export_close(
  value : @publication_host.PublicationOutputExport,
) -> Unit {
  value.cancel()
}
