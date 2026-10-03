///|
#export_name("clientProgramEffectInferOccurrence")
pub fn client_program_effect_infer_occurrence(
  prepared : @publication_host.PreparedClientEffectComputation,
) -> @publication_host.ClientInferOccurrence? {
  @publication_host.prepared_client_effect_infer_occurrence(prepared)
}

///|
#export_name("clientProgramPrepareEffectInferSegments")
pub fn client_program_prepare_effect_infer_segments(
  prepared : @publication_host.PreparedClientEffectComputation,
  occurrence : @publication_host.ClientInferOccurrence,
  registry : String,
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
      registry,
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
      registry,
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
#export_name("clientProgramComposedInferLocalProvider")
pub fn client_program_composed_infer_local_provider(
  occurrence : @publication_host.ClientInferOccurrence,
  open : (Array[@local.ManagedProviderInput]) -> @infer_host.Execution?,
  observe_issue : (@infer_host.Issue) -> Unit,
  retain_completed : (@infer_host.Execution) -> Bool,
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
  )
}

///|
#export_name("clientProgramAdmitComposedInferSources")
pub fn client_program_admit_composed_infer_sources(
  occurrence : @publication_host.ClientInferOccurrence,
  captures : Array[@query.CapturedInputSource],
  identities : Array[@query.CapturedSourceRelationIdentity],
  requirements : Array[@planning.QueryRequirement],
  logical_wires : Array[String],
  evidence_wires : Array[String],
  authority_scope_cid : String,
  started_at : String,
  completed_at : String,
) -> Result[
  @publication_host.ClientInferComposedSources,
  @publication_host.ClientInferCallScopeIssue,
] {
  if logical_wires.length() != 2 || evidence_wires.length() != 2 {
    return Err(@publication_host.ForeignInput)
  }
  let logicals = []
  let evidence = []
  for index in 0..<2 {
    let logical = match
      @publication.admit_run_evidence_value(
        "source_input_logical",
        logical_wires[index],
        100000,
        10000,
        100,
      ) {
      Ok(value) => value
      Err(issue) => return Err(@publication_host.Evidence(issue))
    }
    let source = match
      @publication.admit_run_evidence_value(
        "source_evidence",
        evidence_wires[index],
        100000,
        10000,
        100,
      ) {
      Ok(value) => value
      Err(issue) => return Err(@publication_host.Evidence(issue))
    }
    logicals.push(logical)
    evidence.push(source)
  }
  @publication_host.admit_client_infer_composed_sources(
    occurrence, captures, identities, requirements, logicals, evidence, authority_scope_cid,
    started_at, completed_at,
  )
}

///|
#export_name("clientProgramOpenMultiCapturedInferEffectHost")
pub fn client_program_open_multi_captured_infer_effect_host(
  prepared : @publication_host.PreparedClientEffectRun,
  sources : Array[@query.CapturedInputSource],
  ledger : @resources.Ledger,
  registry : String,
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
    registry,
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
/// Refresh the original acquired Effect DAG after installed output cleanup
/// and both Source issuers have closed. This observes their release facts;
/// revocation alone cannot return the ledger's retained bytes or scratch.
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
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  usage.held_bytes == 0L &&
  usage.reserved_transfer_bytes == 0L &&
  usage.reserved_retention_bytes == 0L &&
  usage.reserved_execution_bytes == 0L &&
  usage.uncertain_transfer_bytes == 0L
}
