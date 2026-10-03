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
