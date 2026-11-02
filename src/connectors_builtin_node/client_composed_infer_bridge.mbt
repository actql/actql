///|
#export_name("clientProgramEffectInferOccurrence")
pub fn client_program_effect_infer_occurrence(
  prepared : @publication_host.PreparedClientEffectComputation,
) -> @publication_host.ClientInferOccurrence? {
  @publication_host.prepared_client_effect_infer_occurrence(prepared)
}

///|
#export_name("clientProgramComposedInferOccurrences")
pub fn client_program_composed_infer_occurrences(
  prepared : @publication_host.PreparedClientProgram,
) -> Result[Array[@publication_host.ClientInferOccurrence], @infer_host.Issue] {
  match @publication_host.prepared_client_composed_infer_occurrences(prepared) {
    Some(occurrences) => Ok(occurrences)
    None => Err(@infer_host.InvalidAdvance)
  }
}

///|
#export_name("clientProgramPrepareComposedInferSegments")
pub fn client_program_prepare_composed_infer_segments(
  prepared : @publication_host.PreparedClientProgram,
  occurrence : @publication_host.ClientInferOccurrence,
  sequence_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values : String,
  fragment : String,
  ordered : String,
) -> Result[
  (@execution.GeneratedSequence, @execution.GeneratedSequence?),
  @infer_host.Issue,
] {
  guard @client_local_host.prepare_client_composed_infer_prefix(
      prepared,
      occurrence,
      sequence_contracts,
      values,
      fragment_body=Some(fragment),
      ordered_body=Some(ordered),
    )
    is Some(prefix) else {
    return Err(@infer_host.InvalidAdvance)
  }
  if @publication_host.client_infer_occurrence_terminal(occurrence) {
    return Ok((prefix, None))
  }
  guard @client_local_host.prepare_client_composed_infer_suffix(
      prepared,
      occurrence,
      sequence_contracts,
      values,
      fragment_body=Some(fragment),
      ordered_body=Some(ordered),
    )
    is Some(suffix) else {
    return Err(@infer_host.InvalidAdvance)
  }
  Ok((prefix, Some(suffix)))
}

///|
/// A generated Content input owns its prefix separately. Prepare only the
/// same checked consumer's suffix; never reinterpret Serialize as pure Compute.
#export_name("clientProgramPrepareComposedInferComputeSuffix")
pub fn client_program_prepare_composed_infer_compute_suffix(
  prepared : @publication_host.PreparedClientProgram,
  occurrence : @publication_host.ClientInferOccurrence,
  sequence_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values : String,
  fragment : String,
  ordered : String,
) -> Result[@execution.GeneratedSequence?, @infer_host.Issue] {
  guard @publication_host.client_infer_occurrence_matches(occurrence, prepared) else {
    return Err(@infer_host.InvalidAdvance)
  }
  if @publication_host.client_infer_occurrence_terminal(occurrence) {
    return Ok(None)
  }
  match
    @client_local_host.prepare_client_composed_infer_suffix(
      prepared,
      occurrence,
      sequence_contracts,
      values,
      fragment_body=Some(fragment),
      ordered_body=Some(ordered),
    ) {
    Some(suffix) => Ok(Some(suffix))
    None => Err(@infer_host.InvalidAdvance)
  }
}

///|
#export_name("clientProgramCompileLocalInfers")
pub fn client_program_compile_local_infers(
  prepared : @publication_host.PreparedClientProgram,
  graphs : Array[@publication_host.ClientInferPlanGraph],
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
    Ok(manifests) => manifests
    Err(issue) => return Err(Manifests(issue))
  }
  @publication_host.issue_prepared_client_multi_infer_compilation(
    prepared,
    graphs,
    manifests,
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    10000,
    1000000,
    100000,
    100,
  ).map_err(issue => Compilation(issue))
}

///|
#export_name("clientProgramStartCompleteInferObservationIssuance")
pub fn client_program_start_complete_infer_observation_issuance(
  executions : Array[@infer_host.Execution],
  ledger : @resources.Ledger,
  max_slots : Int,
  max_wire_bytes : Int,
  max_work : Int,
) -> Result[@infer_host.ObservationIssuance, @infer_host.Issue] {
  @infer_host.start_complete_observation_issuance(executions, ledger, {
    max_slots,
    max_wire_bytes,
    max_work,
  })
}

///|
/// Complete inventories stay opaque across the installing adapter. No JSON
/// metadata substitutes for the live generation or adopted Model slot owners.
#export_name("clientProgramStartContentInferObservationIssuance")
pub fn client_program_start_content_infer_observation_issuance(
  executions : Array[@infer_host.Execution],
  generations : Array[@publication_host.ClientSerializationGeneration],
  ledger : @resources.Ledger,
  max_slots : Int,
  max_wire_bytes : Int,
  max_work : Int,
) -> Result[@infer_host.ObservationIssuance, @infer_host.Issue] {
  @infer_host.start_complete_observation_issuance(
    executions,
    ledger,
    { max_slots, max_wire_bytes, max_work, },
    generations~,
  )
}

///|
#export_name("clientProgramOpenCapturedComposedInferHost")
pub fn client_program_open_captured_composed_infer_host(
  prepared : @publication_host.PreparedClientProgram,
  source : @query.CapturedInputSource,
  sequence_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values : String,
  fragment : String?,
  ordered : String?,
  providers : Array[@local.ManagedProvider],
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  @client_local_host.open_captured_local_retained_host(
    prepared,
    source,
    sequence_contracts,
    values,
    1L,
    0L,
    0L,
    0L,
    fragment_body=fragment,
    ordered_body=ordered,
    provider_factory=capacity => {
      let families = installed_client_family_providers(capacity)
      for provider in providers {
        families.push(provider)
      }
      families
    },
  )
}

///|
/// Source-free Mock components use the same admitted Run as their Local
/// driver. Provider construction does not create a replacement Ledger.
#export_name("clientProgramOpenInstalledManagedSourceFreeComposedInferHost")
pub fn client_program_open_installed_managed_source_free_composed_infer_host(
  value : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  sequence_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values : String,
  fragment : String?,
  ordered : String?,
  providers : Array[@local.ManagedProvider],
) -> Result[
  @builtin.ConfiguredComputeHost[@strategy.RunIssue]?,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.open_installed_managed_source_free_host(
    value,
    prepared,
    request,
    sequence_contracts,
    values,
    fragment,
    ordered,
    true,
    provider_factory=capacity => {
      let families = installed_client_family_providers(capacity)
      for provider in providers {
        families.push(provider)
      }
      families
    },
  )
}

///|
/// Both captured Sources and the Mock component borrow the already admitted
/// Run. The Local driver remains the only scheduler; no scalar fallback or
/// new resource parent is constructed by this provider connection.
#export_name("clientProgramOpenMultiCapturedComposedInferHost")
pub fn client_program_open_multi_captured_composed_infer_host(
  prepared : @publication_host.PreparedClientProgram,
  sources : Array[@query.CapturedInputSource],
  ledger : @resources.Ledger,
  sequence_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values : String,
  fragment : String?,
  ordered : String?,
  providers : Array[@local.ManagedProvider],
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  if sources.length() != 2 {
    return None
  }
  @client_local_host.open_multi_captured_local_retained_host(
    prepared,
    [(0, sources[0]), (1, sources[1])],
    ledger,
    sequence_contracts,
    values,
    fragment,
    ordered,
    provider_factory=capacity => {
      let families = installed_client_family_providers(capacity)
      for provider in providers {
        families.push(provider)
      }
      families
    },
  )
}

///|
#export_name("clientProgramPrepareEffectInferSegments")
pub fn client_program_prepare_effect_infer_segments(
  prepared : @publication_host.PreparedClientEffectComputation,
  occurrence : @publication_host.ClientInferOccurrence,
  sequence_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values : String,
  fragment : String,
  ordered : String,
) -> Result[
  (@execution.GeneratedSequence, @execution.GeneratedSequence?),
  @infer_host.Issue,
] {
  guard @client_local_host.prepare_client_effect_infer_prefix(
      prepared,
      occurrence,
      sequence_contracts,
      values,
      fragment_body=Some(fragment),
      ordered_body=Some(ordered),
    )
    is Some(prefix) else {
    return Err(@infer_host.InvalidAdvance)
  }
  if @publication_host.client_infer_occurrence_terminal(occurrence) {
    return Ok((prefix, None))
  }
  guard @client_local_host.prepare_client_effect_infer_suffix(
      prepared,
      occurrence,
      sequence_contracts,
      values,
      fragment_body=Some(fragment),
      ordered_body=Some(ordered),
    )
    is Some(suffix) else {
    return Err(@infer_host.InvalidAdvance)
  }
  let limits = @infer_host.standard_limits()
  if @local.local_bounded_relation_provider(
      limits.input,
      limits.measurement,
      suffix,
    )
    is None {
    return Err(@infer_host.InvalidAdvance)
  }
  Ok((prefix, Some(suffix)))
}

///|
#export_name("clientProgramInferOccurrenceCoordinates")
pub fn client_program_infer_occurrence_coordinates(
  occurrence : @publication_host.ClientInferOccurrence,
) -> (Int, Int, Int) {
  @publication_host.client_infer_occurrence_coordinates(occurrence)
}

///|
#export_name("clientProgramInferOccurrenceModelTaskCid")
pub fn client_program_infer_occurrence_model_task_cid(
  occurrence : @publication_host.ClientInferOccurrence,
) -> String? {
  @publication_host.client_infer_occurrence_model_task_cid(occurrence)
}

///|
#export_name("clientProgramReadComposedInferModelExecution")
pub fn client_program_read_composed_infer_model_execution(
  occurrence : @publication_host.ClientInferOccurrence,
  body : String,
  expected_cid : String,
) -> Result[
  @check_environment.ModelExecutionContract,
  @publication_host.ClientInferPlanGraphIssue,
] {
  @publication_host.read_client_infer_occurrence_model_execution(
    occurrence,
    @utf8.encode(body),
    expected_cid,
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 10000, },
    1000000,
  )
}

///|
#export_name("clientProgramInstalledComposedInferPlanGraph")
pub fn client_program_installed_composed_infer_plan_graph(
  occurrence : @publication_host.ClientInferOccurrence,
  execution : @check_environment.ModelExecutionContract,
) -> Result[
  @publication_host.ClientInferPlanGraph,
  @publication_host.ClientInferPlanGraphIssue,
] {
  @publication_host.issue_installed_client_composed_infer_plan_graph(
    occurrence,
    execution,
    @publication_host.client_standard_values_sequence_limits(),
    100000,
    10000,
    100,
  )
}

///|
#export_name("clientProgramCompileLocalEffectsWithInfer")
pub fn client_program_compile_local_effects_with_infer(
  prepared : @publication_host.PreparedClientEffectComputation,
  graph : @publication_host.ClientInferPlanGraph,
) -> Result[
  @publication_host.ClientEffectCompilation,
  ClientProgramEffectCompilationBridgeIssue,
] {
  compile_client_local_effects(prepared, Some(graph))
}

///|
#export_name("clientProgramEffectAllowedInferRun")
pub fn client_program_effect_allowed_infer_run(
  allowed : @publication_host.ClientEffectAllowedRun,
) -> Result[
  @publication_host.ClientCompiledRun,
  @publication_host.ClientCompiledRunIssue,
] {
  @publication_host.client_effect_allowed_infer_run(allowed)
}

///|
#export_name("clientProgramEffectAllowedSerializationRun")
pub fn client_program_effect_allowed_serialization_run(
  allowed : @publication_host.ClientEffectAllowedRun,
) -> Result[
  @publication_host.ClientCompiledRun,
  @publication_host.ClientCompiledRunIssue,
] {
  @publication_host.client_effect_allowed_serialization_run(allowed)
}

///|
#export_name("clientProgramEffectAllowedInferRunWithPolicyBody")
pub fn client_program_effect_allowed_infer_run_with_policy_body(
  allowed : @publication_host.ClientEffectAllowedRun,
  policy_cid : String,
  policy_wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientCompiledRun,
  @publication_host.ClientCompiledRunIssue,
] {
  @publication_host.client_effect_allowed_infer_run_with_policy_body(
    allowed,
    Some(policy_cid),
    Some(policy_wire),
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
#export_name("clientProgramAdmitSourceFreeResultPolicyBody")
pub fn client_program_admit_source_free_result_policy_body(
  cid : String,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(String, String, String), @publication_host.ClientCompiledRunIssue] {
  match
    @publication_host.admit_source_free_result_policy_body(
      cid, wire, max_bytes, max_nodes, max_depth,
    ) {
    Ok(body) =>
      Ok(
        (
          @publication.captured_effect_dependency_body_kind(body),
          @publication.captured_effect_dependency_body_cid(body),
          @publication.captured_effect_dependency_body_json(body),
        ),
      )
    Err(issue) => Err(issue)
  }
}

///|
/// Retain the actual source-free Result Policy original with the admitted
/// INFER Run. The Effect inventory must use this body, not Model egress.
#export_name("clientProgramCompiledRunSourceFreeResultPolicy")
pub fn client_program_compiled_run_source_free_result_policy(
  compiled : @publication_host.ClientCompiledRun,
) -> (String, String, String)? {
  guard @publication_host.client_compiled_run_source_free_result_policy_body(
      compiled,
    )
    is Some(body) else {
    return None
  }
  Some(
    (
      @publication.captured_effect_dependency_body_kind(body),
      @publication.captured_effect_dependency_body_cid(body),
      @publication.captured_effect_dependency_body_json(body),
    ),
  )
}

///|
#export_name("clientProgramCompiledRunEvaluationPolicy")
pub fn client_program_compiled_run_evaluation_policy(
  compiled : @publication_host.ClientCompiledRun,
) -> (String, String, String)? {
  @publication_host.client_compiled_run_evaluation_policy_body(compiled)
}

///|
#export_name("clientProgramInferOccurrenceTargetName")
pub fn client_program_infer_occurrence_target_name(
  occurrence : @publication_host.ClientInferOccurrence,
) -> String? {
  @publication_host.client_infer_occurrence_target_name(occurrence)
}

///|
#export_name("clientProgramCompiledRunEffectMatches")
pub fn client_program_compiled_run_effect_matches(
  compiled : @publication_host.ClientCompiledRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  compilation : @publication_host.ClientEffectCompilation,
) -> Bool {
  @publication_host.client_compiled_run_matches_effect(
    compiled, prepared, compilation,
  )
}

///|
#export_name("clientProgramCheckCompiledRunDefinition")
pub fn client_program_check_compiled_run_definition(
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Bool {
  @publication_host.check_client_compiled_run_definition(compiled, definition)
  is Ok(_)
}

///|
#export_name("clientProgramCheckCompiledLocalExecutionOwner")
pub fn client_program_check_compiled_local_execution_owner(
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Bool {
  @publication_host.client_compiled_local_execution_owner(compiled, definition)
}

///|
#export_name("clientProgramAdmitComposedInferEgress")
pub fn client_program_admit_composed_infer_egress(
  occurrence : @publication_host.ClientInferOccurrence,
  execution : @check_environment.ModelExecutionContract,
  observe : () -> (String, String, Bool, Bool)?,
) -> Result[
  @publication_host.ClientInferEgressAdmission,
  @publication_host.ClientInferEgressIssue,
] {
  @publication_host.admit_client_infer_occurrence_egress(
    occurrence,
    execution,
    () => client_infer_egress_observation(observe()),
  )
}

///|
#export_name("clientProgramStartComposedInferExecution")
pub fn client_program_start_composed_infer_execution(
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
  prefix : @execution.GeneratedSequence,
  inputs : Array[@local.ManagedProviderInput],
  provider : @model.ModelProvider,
  sources : @publication_host.ClientInferComposedSources?,
) -> Result[@infer_host.Execution, @infer_host.Issue] {
  @infer_host.start_composed(
    occurrence,
    graph,
    prefix,
    inputs,
    provider,
    @infer_host.standard_limits(),
    sources~,
  )
}

///|
/// Use the same bounded input owner as the Model component, without dispatch.
/// Captured inputs must carry the matching admitted Source closure.
#export_name("clientProgramStartComposedInferInput")
pub fn client_program_start_composed_infer_input(
  occurrence : @publication_host.ClientInferOccurrence,
  prefix : @execution.GeneratedSequence,
  inputs : Array[@local.ManagedProviderInput],
  sources : @publication_host.ClientInferComposedSources?,
) -> Result[
  @client_local_host.ClientInferInputExecution,
  @client_local_host.ClientInferInputIssue,
] {
  if (
      sources is Some(value) &&
      !@publication_host.client_infer_composed_sources_matches(
        value, occurrence,
      )
    ) ||
    (
      @publication_host.client_infer_occurrence_has_captured_sources(occurrence) &&
      sources is None
    ) {
    return Err(@client_local_host.UnsupportedProgram)
  }
  let limits = @infer_host.standard_limits()
  @client_local_host.start_client_composed_infer_input(
    occurrence,
    prefix,
    inputs,
    limits.input,
    limits.measurement,
    limits.mapping,
    keyed=sources.bind(value => {
      @publication_host.client_infer_composed_keyed_lookup(value, occurrence)
    }),
  )
}

///|
#export_name("clientProgramStartKeyedInferExecution")
pub fn client_program_start_keyed_infer_execution(
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
  prefix : @execution.GeneratedSequence,
  provider : @model.ModelProvider,
  sources : @publication_host.ClientInferComposedSources,
  suffix : @execution.GeneratedSequence?,
  ledger : @resources.Ledger,
) -> Result[@infer_host.Execution, @infer_host.Issue] {
  @infer_host.start_keyed(
    occurrence,
    graph,
    prefix,
    provider,
    @infer_host.standard_limits(),
    sources,
    suffix,
    ledger,
  )
}

///|
#export_name("clientProgramAdvanceInferRoot")
pub fn client_program_advance_infer_root(
  active : @infer_host.Execution,
  quantum : Int,
) -> Result[@infer_host.Poll, @infer_host.Issue] {
  @infer_host.advance_root(active, quantum)
}

///|
#export_name("clientProgramComposedInferLocalProvider")
pub fn client_program_composed_infer_local_provider(
  occurrence : @publication_host.ClientInferOccurrence,
  open : (Array[@local.ManagedProviderInput]) -> @infer_host.Execution?,
  observe_issue : (@infer_host.Issue) -> Unit,
  retain_completed : (@infer_host.Execution) -> Bool,
  allow_cleanup : (@infer_host.Execution) -> Bool,
  input_prefix : @execution.GeneratedSequence?,
) -> @local.ManagedProvider {
  client_infer_local_provider(
    occurrence,
    open,
    observe_issue,
    retain_completed,
    allow_cleanup,
    false,
    input_prefix~,
  )
}

///|
#export_name("clientProgramGeneratedInferLocalProvider")
pub fn client_program_generated_infer_local_provider(
  occurrence : @publication_host.ClientInferOccurrence,
  open : (Array[@local.ManagedProviderInput]) -> @infer_host.Execution?,
  observe_issue : (@infer_host.Issue) -> Unit,
  retain_completed : (@infer_host.Execution) -> Bool,
  allow_cleanup : (@infer_host.Execution) -> Bool,
) -> @local.ManagedProvider {
  client_infer_local_provider(
    occurrence, open, observe_issue, retain_completed, allow_cleanup, true,
  )
}

///|
fn client_infer_local_provider(
  occurrence : @publication_host.ClientInferOccurrence,
  open : (Array[@local.ManagedProviderInput]) -> @infer_host.Execution?,
  observe_issue : (@infer_host.Issue) -> Unit,
  retain_completed : (@infer_host.Execution) -> Bool,
  allow_cleanup : (@infer_host.Execution) -> Bool,
  boundary_only : Bool,
  input_prefix? : @execution.GeneratedSequence? = None,
) -> @local.ManagedProvider {
  @infer_host.composed_local_provider(
    occurrence,
    @infer_host.standard_limits(),
    inputs => {
      match open(inputs) {
        Some(active) => Ok(active)
        None => Err(@infer_host.InvalidAdvance)
      }
    },
    issue => {
      observe_issue(issue)
      @connector.ComputeUnsupported
    },
    retain_completed~,
    allow_cleanup~,
    boundary_only~,
    input_prefix~,
  )
}

///|
#export_name("clientProgramAdmitComposedInferSources")
pub fn client_program_admit_composed_infer_sources(
  occurrence : @publication_host.ClientInferOccurrence,
  captures : Array[@query.CapturedInputSource],
  identities : Array[@query.CapturedSourceRelationIdentity],
  requirements : Array[@planning.QueryRequirement],
  logicals : Array[@publication.RunEvidenceValue],
  evidence : Array[@publication.RunEvidenceValue],
  authority_scope_cid : String,
  started_at : String,
  completed_at : String,
  keyed : @publication_host.ClientKeyedLookupObservation?,
) -> Result[
  @publication_host.ClientInferComposedSources,
  @publication_host.ClientInferCallScopeIssue,
] {
  let count = logicals.length()
  if count < 1 || count > 2 || evidence.length() != count {
    return Err(@publication_host.ForeignInput)
  }
  for index in 0..<count {
    match
      check_client_infer_original_evidence(
        "source_input_logical",
        logicals[index],
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    match
      check_client_infer_original_evidence("source_evidence", evidence[index]) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  @publication_host.admit_client_infer_composed_sources(
    occurrence,
    captures,
    identities,
    requirements,
    logicals,
    evidence,
    authority_scope_cid,
    started_at,
    completed_at,
    keyed~,
  )
}

///|
#export_name("clientProgramOpenMultiCapturedInferEffectHost")
pub fn client_program_open_multi_captured_infer_effect_host(
  prepared : @publication_host.PreparedClientEffectRun,
  sources : Array[@query.CapturedInputSource],
  ledger : @resources.Ledger,
  sequence_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values : String,
  fragment : String?,
  ordered : String?,
  provider : @local.ManagedProvider,
) -> ClientLocalEffectHost? {
  if sources.length() != 2 {
    return None
  }
  open_client_local_effect_host(
    prepared,
    None,
    sequence_contracts,
    values,
    1L,
    0L,
    0L,
    0L,
    fragment_body=fragment,
    ordered_body=ordered,
    captured_sources=[(0, sources[0]), (1, sources[1])],
    acquisition_ledger=Some(ledger),
    component_providers=[provider],
  )
}

///|
/// Connect the existing Model component to the original source-free Effect
/// DAG. Its input is the checked producer port; it is not a captured Source.
#export_name("clientProgramOpenSourceFreeInferEffectHost")
pub fn client_program_open_source_free_infer_effect_host(
  prepared : @publication_host.PreparedClientEffectRun,
  sequence_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values : String,
  fragment : String?,
  ordered : String?,
  provider : @local.ManagedProvider,
) -> ClientLocalEffectHost? {
  open_client_local_effect_host(
    prepared,
    None,
    sequence_contracts,
    values,
    1L,
    0L,
    0L,
    0L,
    fragment_body=fragment,
    ordered_body=ordered,
    component_providers=[provider],
  )
}

///|
/// Refresh the original acquired Effect DAG after installed output cleanup
/// and Source issuers have closed. Inspect this DAG's tracked task obligations;
/// its shared Ledger may still contain the SAME Run's preparation and spent
/// operation controls. Their original Run owner retires them separately after
/// this physical/task boundary; no ledger reservation is forgiven here.
#export_name("clientProgramRefreshAcquiredEffectCleanup")
pub fn client_program_refresh_acquired_effect_cleanup(
  value : ClientLocalEffectHost,
) -> Bool {
  let run = @strategy.captured_effect_run_dag(value.run)
  @strategy.stop_captured_dag(run)
  let count = @strategy.graph_task_count(@strategy.captured_dag_graph(run))
  for task = count - 1; task >= 0; task = task - 1 {
    @strategy.close_captured_task_output(run, task)
  }
  @strategy.refresh_captured_retention(run)
  !@strategy.captured_task_retirement_pending(run)
}
