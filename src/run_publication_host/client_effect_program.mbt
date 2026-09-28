///|
/// Host-selected bounds for an Effectful computation. Static closure is only
/// preparation: current grants, captured values, Preview and apply remain
/// separate obligations.
pub(all) struct ClientEffectComputationLimits {
  program : ClientProgramPreparationLimits
  max_members : Int
  max_header_work : Int
  mapping : @environment.Limits
  max_mapping_work : Int
  effects : @stage_results.EffectStaticCandidateLimits
}

///|
pub(all) enum ClientEffectComputationIssue {
  Syntax(@syntax.SyntaxError)
  Candidate(@checked.EffectComputationIssue)
  Mapping(@environment.MappingShapeIssue)
  Static(@stage_results.EffectStaticCandidateIssue)
  Stage(ClientStageOwnerIssue)
  Graph(@strategy.GraphIssue)
}

///|
/// The ordinary checked computation and its exact static Effect inventory
/// share one Program owner. This is not an executable Effect Run or permit.
struct PreparedClientEffectComputation {
  source : @syntax.Program
  candidate : @checked.EffectProgramStaticCandidate
  graph : @strategy.CheckedEffectComputationDAG
  check_environment_cid : String
}

///|
pub fn prepare_client_effect_computation(
  document : String,
  format : @syntax.Format,
  environment : @checked.CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  limits : ClientEffectComputationLimits,
) -> Result[PreparedClientEffectComputation, ClientEffectComputationIssue] {
  let parsed = match
    @syntax.parse(document, limits.program.checking.input, format~) {
    Ok(value) => value
    Err(issue) => return Err(Syntax(issue))
  }
  let computation = match
    @checked.prepare_effect_computation_candidate(
      parsed,
      environment,
      supplied,
      evidence,
      limits.program.checking,
      limits.max_members,
      limits.max_header_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Candidate(issue))
  }
  let mappings = match
    @environment.check_mapping_contract_shapes(
      @checked.effect_computation_environment(computation),
      limits.mapping,
      limits.max_mapping_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Mapping(issue))
  }
  let candidate = match
    @checked.close_effect_computation_static(
      computation,
      mappings,
      limits.effects,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Static(issue))
  }
  let checked = @checked.effect_program_static_checked_computation(candidate)
  let owners = match prepare_client_stage_owners(checked, limits.program) {
    Ok(value) => value
    Err(issue) => return Err(Stage(issue))
  }
  let graph = match
    @strategy.prepare_checked_effect_computation_dag(
      candidate,
      owners,
      limits.program.max_tasks,
      limits.program.max_graph_work,
      source_free_root=owners.length() > 0 &&
        @pipeline.starts_with_values(
          @lower.pipeline(@lower.bound_preparation(owners[0])),
        ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Graph(issue))
  }
  Ok({
    source: parsed,
    candidate,
    graph,
    check_environment_cid: @checked.checking_environment_cid(environment),
  })
}

///|
pub fn prepared_client_effect_computation_graph(
  value : PreparedClientEffectComputation,
) -> @strategy.CheckedEffectComputationDAG {
  value.graph
}

///|
/// The checked Result inventory is available before Run acceptance. Reading
/// it does not compile a second Program or grant execution authority.
pub fn prepared_client_effect_result_count(
  value : PreparedClientEffectComputation,
) -> Int {
  @strategy.graph_result_count(
    @strategy.checked_effect_computation_graph(value.graph),
  )
}

///|
pub fn prepared_client_effect_result_name(
  value : PreparedClientEffectComputation,
  index : Int,
) -> String? {
  @strategy.graph_result_name(
    @strategy.checked_effect_computation_graph(value.graph),
    index,
  )
}

///|
pub fn prepared_client_effect_computation_candidate(
  value : PreparedClientEffectComputation,
) -> @checked.EffectProgramStaticCandidate {
  value.candidate
}

///|
pub fn prepared_client_effect_computation_source(
  value : PreparedClientEffectComputation,
) -> @syntax.Program {
  value.source
}

///|
pub fn prepared_client_effect_computation_environment_cid(
  value : PreparedClientEffectComputation,
) -> String {
  value.check_environment_cid
}

///|
pub fn prepared_client_effect_computation_definition_cid(
  value : PreparedClientEffectComputation,
) -> String {
  @checked.effect_program_static_definition_cid(value.candidate)
}

///|
pub fn prepared_client_effect_computation_semantics_cid(
  value : PreparedClientEffectComputation,
) -> String {
  @checked.effect_program_static_semantics_cid(value.candidate)
}

///|
pub fn prepared_client_effect_identity(
  value : PreparedClientEffectComputation,
) -> ClientProgramIdentity {
  let checked = @checked.effect_program_static_checked_computation(
    value.candidate,
  )
  let source = @checked.source_identity(checked)
  {
    program_definition_cid: @context.program_identity_definition_cid(source),
    parameter_values_cid: @context.program_identity_parameter_values_cid(source),
  }
}

///|
/// Admit an Effectful Run only when the template, prepared invocation,
/// authorization, and compiled plan bind the exact checked Effect owner.
/// This is Run admission, not a Preview or mutation permit.
pub fn admit_prepared_client_effect_run_publication(
  value : PreparedClientEffectComputation,
  template : @publication.RunEvidenceValue,
  prepared : @publication.RunEvidenceValue,
  authorization : @publication.RunEvidenceValue,
  compiled_plan : @publication.PublicationContract,
) -> Result[
  @publication.RunPublicationAdmission,
  @publication.RunPublicationAdmissionIssue,
] {
  let identity = prepared_client_effect_identity(value)
  @publication.admit_checked_run_publication(
    template,
    prepared,
    authorization,
    compiled_plan,
    identity.program_definition_cid,
    identity.parameter_values_cid,
    prepared_client_effect_computation_semantics_cid(value),
    prepared_client_effect_computation_environment_cid(value),
  )
}

///|
/// Bind the prepared computation to its admitted exact Run. This preserves
/// the Effect closure instead of passing only its graph to a source-free Host.
pub(all) enum ClientEffectRunIssue {
  Admission(@checked.EffectProgramRunIssue)
  Binding(@strategy.RunIssue)
}

///|
struct PreparedClientEffectRun {
  computation : PreparedClientEffectComputation
  checked : @strategy.CheckedEffectRunDAG
}

///|
pub fn bind_prepared_client_effect_run(
  computation : PreparedClientEffectComputation,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
) -> Result[PreparedClientEffectRun, ClientEffectRunIssue] {
  let owner = match
    @checked.bind_effect_program_static_run(
      computation.candidate,
      admission,
      run_definition,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Admission(issue))
  }
  let checked = match
    @strategy.bind_checked_effect_run_dag(computation.graph, owner) {
    Ok(value) => value
    Err(issue) => return Err(Binding(issue))
  }
  Ok({ computation, checked, })
}

///|
pub fn prepared_client_effect_run_graph(
  value : PreparedClientEffectRun,
) -> @strategy.CheckedEffectRunDAG {
  value.checked
}

///|
pub fn prepared_client_effect_run_computation(
  value : PreparedClientEffectRun,
) -> PreparedClientEffectComputation {
  value.computation
}

///|
/// Open only a source-free checked Effect Run. This creates an in-memory
/// compute owner after exact Run admission; it is not a mutation permit.
pub fn open_prepared_source_free_client_effect_run(
  value : PreparedClientEffectRun,
  limits : @resources.LedgerLimits,
) -> Result[@strategy.CapturedEffectRunDAG, ClientRunOpenIssue] {
  let ledger = match @resources.create_ledger(limits) {
    Ok(value) => value
    Err(issue) => return Err(Ledger(issue))
  }
  @strategy.open_source_free_effect_run_dag(value.checked, ledger).map_err(issue => {
    Run(issue)
  })
}

///|
/// Compile an Effectful task through the same checked Local lowering as an
/// Effect-free task, without discarding its static Effect owner.
pub fn prepare_client_effect_task_sequence(
  value : PreparedClientEffectComputation,
  task : Int,
  contracts : @execution.RegisteredRelationContracts,
  contexts : Array[@execution.FragmentRuntimeContext],
  limits : @lower.SequenceLimits,
  max_work : Int,
  max_entries : Int,
) -> Result[@execution.GeneratedSequence, ClientTaskSequenceIssue] {
  prepare_client_task_sequence_graph(
    @strategy.checked_effect_computation_graph(value.graph),
    task,
    contracts,
    contexts,
    limits,
    max_work,
    max_entries,
  )
}
