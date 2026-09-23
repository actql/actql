///|
/// Host-selected limits for checking and lowering one Effect-free document.
/// They do not grant execution, publication or retained storage.
pub(all) struct ClientProgramPreparationLimits {
  checking : @checked.CheckLimits
  lowering : @lower.Limits
  max_parameters : Int
  max_parameter_name_bytes : Int
  max_tasks : Int
  max_graph_work : Int
}

///|
pub(all) enum ClientProgramPreparationIssue {
  Syntax(@syntax.SyntaxError)
  EffectNotSupported(String)
  NeedsInputs
  Check(@checked.LocalConstructionFailure)
  MissingCheckedStage(Int)
  MissingStageIdentity(Int)
  Lowering(@lower.Issue)
  Binding(@lower.BindingIssue)
  Graph(@strategy.GraphIssue)
}

///|
/// The checked graph owns the declared Result inventory. This value is a
/// preparation, not a durable Run acceptance or a physical Site selection.
struct PreparedClientProgram {
  graph : @strategy.CheckedDAG
}

///|
/// Checked identity components of one prepared Program. Request admission
/// additionally binds scope, authority, grants, owner and durability; these
/// two CIDs alone are not a complete Client request fingerprint.
pub(all) struct ClientProgramIdentity {
  program_definition_cid : String
  parameter_values_cid : String
} derive(Eq, Debug)

///|
pub fn prepared_client_identity(
  value : PreparedClientProgram,
) -> ClientProgramIdentity {
  let source = @checked.source_identity(@strategy.graph_program(value.graph))
  {
    program_definition_cid: @context.program_identity_definition_cid(source),
    parameter_values_cid: @context.program_identity_parameter_values_cid(source),
  }
}

///|
pub fn prepared_client_graph(
  value : PreparedClientProgram,
) -> @strategy.CheckedDAG {
  value.graph
}

///|
pub(all) enum ClientRunOpenIssue {
  Ledger(@resources.LedgerIssue)
  Run(@strategy.RunIssue)
}

///|
/// Open an admitted source-free preparation in the existing checked task
/// lifecycle. The Host must durably admit a Client request before starting
/// physical work; opening this in-memory task owner is not that admission.
pub fn open_prepared_source_free_client_run(
  value : PreparedClientProgram,
  limits : @resources.LedgerLimits,
) -> Result[@strategy.CapturedDAG, ClientRunOpenIssue] {
  let ledger = match @resources.create_ledger(limits) {
    Ok(value) => value
    Err(issue) => return Err(Ledger(issue))
  }
  @strategy.open_source_free_dag(value.graph, ledger).map_err(issue => {
    Run(issue)
  })
}

///|
pub fn prepared_client_result_count(value : PreparedClientProgram) -> Int {
  @strategy.graph_result_count(value.graph)
}

///|
pub fn prepared_client_result_name(
  value : PreparedClientProgram,
  index : Int,
) -> String? {
  @strategy.graph_result_name(value.graph, index)
}

///|
pub(all) enum ClientTaskSequenceIssue {
  MissingTask
  EmptyTask
  Sequence(@lower.SequenceIssue)
  Generated(@execution.SequenceRunIssue)
}

///|
/// Compile the exact checked task owner for an installed Local realization.
/// Runtime expression contexts and registered contracts remain explicit
/// adapter inputs; this does not select a Site or grant execution.
pub fn prepare_client_task_sequence(
  value : PreparedClientProgram,
  task : Int,
  contracts : @execution.RegisteredRelationContracts,
  contexts : Array[@execution.FragmentRuntimeContext],
  limits : @lower.SequenceLimits,
  max_work : Int,
  max_entries : Int,
) -> Result[@execution.GeneratedSequence, ClientTaskSequenceIssue] {
  guard @strategy.graph_task_owner(value.graph, task) is Some(owner) else {
    return Err(MissingTask)
  }
  let sequence = match @lower.prepare_sequence(owner, limits) {
    Ok(result) => result
    Err(issue) => return Err(Sequence(issue))
  }
  let count = @lower.sequence_count(sequence)
  if count == 0 {
    return Err(EmptyTask)
  }
  guard @lower.node_at(@lower.bound_preparation(owner), count - 1) is Some(last) else {
    return Err(EmptyTask)
  }
  match
    @execution.prepare_generated_sequence(
      contracts,
      sequence,
      contexts,
      [@lower.node_id(last)],
      max_work,
      max_entries,
    ) {
    Ok(generated) => Ok(generated)
    Err(issue) => Err(Generated(issue))
  }
}

///|
/// Use the ordinary parser and semantic checker. Every lowered owner is
/// derived from that same CheckedProgram; callers cannot inject a parallel
/// graph, Result list or effect-free claim.
pub fn prepare_effect_free_client_program(
  document : String,
  format : @syntax.Format,
  environment : @checked.CheckEnvironment,
  supplied : @decode.Cursor?,
  limits : ClientProgramPreparationLimits,
) -> Result[PreparedClientProgram, ClientProgramPreparationIssue] {
  let parsed = match @syntax.parse(document, limits.checking.input, format~) {
    Ok(value) => value
    Err(issue) => return Err(Syntax(issue))
  }
  for stage in @syntax.stages(parsed) {
    if !@syntax.effect_names(stage).is_empty() {
      return Err(EffectNotSupported(stage.id))
    }
  }
  let checked = match
    @checked.check_parsed(parsed, environment, supplied, limits.checking) {
    Checked(value) => value
    NeedsInputs(_) => return Err(NeedsInputs)
    Rejected(diagnostic) =>
      return Err(Check(@checked.diagnostic_cause(diagnostic)))
  }
  let identity = @checked.source_identity(checked)
  let selected = @checked.selected_expression_profiles(checked)
  let owners : Array[@lower.BoundPrepared] = []
  for stage in 0..<@checked.unit_count(checked) {
    guard @checked.unit_pipeline(checked, stage) is Some(pipeline) else {
      return Err(MissingCheckedStage(stage))
    }
    let preparation = match @lower.prepare(pipeline, limits.lowering) {
      Ok(value) => value
      Err(issue) => return Err(Lowering(issue))
    }
    guard @context.program_identity_stage_at(identity, stage) is Some(source) else {
      return Err(MissingStageIdentity(stage))
    }
    let parameters = @parameters.bound_values(
      @context.stage_identity_parameter_values(source),
    )
    let owner = match
      @lower.bind_parameters(
        preparation,
        Some(parameters),
        max_parameters=limits.max_parameters,
        max_name_bytes=limits.max_parameter_name_bytes,
        expression_profiles={
          text_time: selected.text_time,
          veca: selected.veca,
        },
      ) {
      Ok(value) => value
      Err(issue) => return Err(Binding(issue))
    }
    owners.push(owner)
  }
  match
    @strategy.prepare_checked_dag(
      checked,
      owners,
      limits.max_tasks,
      limits.max_graph_work,
      source_free_root=owners.length() > 0 &&
        @pipeline.starts_with_values(
          @lower.pipeline(@lower.bound_preparation(owners[0])),
        ),
    ) {
    Ok(graph) => Ok({ graph, })
    Err(issue) => Err(Graph(issue))
  }
}
