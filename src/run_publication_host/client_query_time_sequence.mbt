///|
fn bind_client_query_time_task_sequence(
  prepared : PreparedClientProgram,
  task : Int,
  generated : @execution.GeneratedSequence,
  context : @publication.QueryEvaluationTime,
  max_work : Int,
  max_entries : Int,
) -> Result[@execution.GeneratedSequence, ClientQueryTimeIssue] {
  guard @strategy.graph_task_owner(prepared.graph, task) is Some(owner) &&
    physical_equal(@execution.generated_sequence_owner(generated), owner) else {
    return Err(ForeignPreparation)
  }
  @execution.bind_generated_sequence_query_time(
    generated, context, max_work, max_entries,
  ).map_err(_ => ForeignPreparation)
}

///|
/// Associate the invocation DATA only after checking the same request, Run,
/// Program and exact generated task owner. The reusable sequence is not mutated.
pub fn bind_client_query_time_sequence(
  prepared : PreparedClientProgram,
  task : Int,
  generated : @execution.GeneratedSequence,
  preparation : ClientQueryTimePreparation,
  request : ClientRequestIdentity,
  max_work : Int,
  max_entries : Int,
) -> Result[@execution.GeneratedSequence, ClientQueryTimeIssue] {
  guard preparation.owner is Query(original) &&
    physical_equal(original, prepared) &&
    client_query_time_acquisition_context(preparation, request) is Some(context) else {
    return Err(ForeignPreparation)
  }
  bind_client_query_time_task_sequence(
    prepared, task, generated, context, max_work, max_entries,
  )
}

///|
/// A sequence's invocation must belong to this exact admitted Effect Run, not
/// merely another Run compiled from the same prepared computation.
pub fn client_effect_run_query_time_matches(
  run : PreparedClientEffectRun,
  preparation : ClientQueryTimePreparation,
  request : ClientRequestIdentity,
) -> Bool {
  guard preparation.owner is Effect(original) &&
    physical_equal(original, run.computation) &&
    client_query_time_acquisition_context(preparation, request) is Some(context) else {
    return false
  }
  let owner = @strategy.checked_effect_run_owner(run.checked)
  @publication.query_evaluation_time_matches(
    context,
    @effect_binding.effect_program_run_admission(owner),
    @effect_binding.effect_program_run_definition(owner),
  )
}

///|
pub fn bind_client_effect_query_time_sequence(
  prepared : PreparedClientEffectComputation,
  task : Int,
  generated : @execution.GeneratedSequence,
  preparation : ClientQueryTimePreparation,
  request : ClientRequestIdentity,
  max_work : Int,
  max_entries : Int,
) -> Result[@execution.GeneratedSequence, ClientQueryTimeIssue] {
  guard preparation.owner is Effect(original) &&
    physical_equal(original, prepared) &&
    client_query_time_acquisition_context(preparation, request) is Some(context) else {
    return Err(ForeignPreparation)
  }
  bind_client_query_time_task_sequence(
    client_effect_program_view(prepared),
    task,
    generated,
    context,
    max_work,
    max_entries,
  )
}
